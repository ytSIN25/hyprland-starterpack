#!/usr/bin/env python3
"""Próximos eventos para la dynamic island (Services/Island.qml).

Lee ~/.config/quickshell/calendar.urls: una URL iCal (p. ej. la "dirección
secreta en formato iCal" de Google Calendar) o una ruta a un .ics por línea;
las líneas con # se ignoran. Imprime JSON con los eventos (no de día
completo) que empiezan entre hace 1 h y dentro de 24 h:
    [{"title": str, "start": epoch_ms, "end": epoch_ms}, ...]

Solo librería estándar. Expande RRULE sencillas (DAILY/WEEKLY/MONTHLY/YEARLY
con INTERVAL, COUNT, UNTIL, BYDAY), respeta EXDATE, RECURRENCE-ID y
STATUS:CANCELLED.
"""
import json
import os
import sys
import urllib.request
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

CONF = os.path.expanduser("~/.config/quickshell/calendar.urls")
WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
LOCAL = datetime.now().astimezone().tzinfo


def read_sources():
    try:
        with open(CONF) as f:
            return [l.strip() for l in f if l.strip() and not l.strip().startswith("#")]
    except FileNotFoundError:
        return []


def fetch(src):
    if src.startswith("webcal://"):
        src = "https://" + src[len("webcal://"):]
    if src.startswith(("http://", "https://")):
        req = urllib.request.Request(src, headers={"User-Agent": "quickshell-island"})
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.read().decode("utf-8", "replace")
    with open(os.path.expanduser(src), encoding="utf-8", errors="replace") as f:
        return f.read()


def unfold(text):
    lines = []
    for raw in text.splitlines():
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def parse_prop(line):
    name_params, _, value = line.partition(":")
    parts = name_params.split(";")
    params = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        params[k.upper()] = v.strip('"')
    return parts[0].upper(), params, value


def parse_dt(value, params):
    """Devuelve (datetime aware o date, tz) — tz es la zona de la hora local."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or len(value) == 8:
        return date(int(value[:4]), int(value[4:6]), int(value[6:8])), None
    dt = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    if value.endswith("Z"):
        return dt.replace(tzinfo=timezone.utc), timezone.utc
    tz = LOCAL
    if "TZID" in params:
        try:
            tz = ZoneInfo(params["TZID"])
        except Exception:
            tz = LOCAL
    return dt.replace(tzinfo=tz), tz


def parse_events(text):
    events, cur = [], None
    for line in unfold(text):
        if line == "BEGIN:VEVENT":
            cur = {"exdates": set()}
        elif line == "END:VEVENT":
            if cur is not None:
                events.append(cur)
            cur = None
        elif cur is not None and ":" in line:
            name, params, value = parse_prop(line)
            if name == "SUMMARY":
                cur["title"] = value.replace("\\,", ",").replace("\\;", ";").replace("\\n", " ")
            elif name in ("DTSTART", "DTEND", "RECURRENCE-ID"):
                cur[name] = parse_dt(value, params)
            elif name == "DURATION":
                cur["DURATION"] = value
            elif name in ("RRULE", "UID", "STATUS"):
                cur[name] = value
            elif name == "EXDATE":
                for v in value.split(","):
                    d, _ = parse_dt(v, params)
                    cur["exdates"].add(d.astimezone(timezone.utc) if isinstance(d, datetime) else d)
    return events


def parse_duration(s):
    sign = -1 if s.startswith("-") else 1
    s = s.lstrip("+-").lstrip("P")
    days = secs = 0
    num = ""
    in_time = False
    for ch in s:
        if ch == "T":
            in_time = True
        elif ch.isdigit():
            num += ch
        else:
            n = int(num or 0)
            num = ""
            if ch == "W": days += 7 * n
            elif ch == "D": days += n
            elif ch == "H" and in_time: secs += 3600 * n
            elif ch == "M" and in_time: secs += 60 * n
            elif ch == "S" and in_time: secs += n
    return sign * timedelta(days=days, seconds=secs)


def nth_weekday(year, month, wd, n):
    if n > 0:
        d = date(year, month, 1)
        d += timedelta(days=(wd - d.weekday()) % 7)
        d += timedelta(weeks=n - 1)
    else:
        nxt = date(year + (month == 12), month % 12 + 1, 1)
        d = nxt - timedelta(days=1)
        d -= timedelta(days=(d.weekday() - wd) % 7)
        d -= timedelta(weeks=-n - 1)
    return d if d.month == month else None


def occurrences(start, tz, rule, window_end):
    """Genera inicios (aware) en hora local de la zona, hasta window_end."""
    r = dict(p.split("=", 1) for p in rule.split(";") if "=" in p)
    freq = r.get("FREQ", "")
    interval = int(r.get("INTERVAL", "1") or 1)
    count = int(r["COUNT"]) if "COUNT" in r else None
    until = None
    if "UNTIL" in r:
        u, _ = parse_dt(r["UNTIL"], {})
        until = u if isinstance(u, datetime) else datetime(u.year, u.month, u.day, 23, 59, 59, tzinfo=tz)
    byday = [d for d in r.get("BYDAY", "").split(",") if d]
    naive = start.replace(tzinfo=None)
    produced = 0

    def emit(nv):
        return nv.replace(tzinfo=tz)

    def candidates():
        if freq == "DAILY":
            k = 0
            while True:
                yield [naive + timedelta(days=k * interval)]
                k += 1
        elif freq == "WEEKLY":
            days = [WEEKDAYS.index(d[-2:]) for d in byday] or [naive.weekday()]
            week0 = naive - timedelta(days=naive.weekday())
            k = 0
            while True:
                wk = week0 + timedelta(weeks=k * interval)
                yield sorted(wk + timedelta(days=d) for d in days)
                k += 1
        elif freq == "MONTHLY":
            k = 0
            while True:
                m0 = naive.month - 1 + k * interval
                y, m = naive.year + m0 // 12, m0 % 12 + 1
                out = []
                if byday:
                    for d in byday:
                        n = int(d[:-2]) if d[:-2] not in ("", "+") else 1
                        dd = nth_weekday(y, m, WEEKDAYS.index(d[-2:]), n)
                        if dd: out.append(datetime.combine(dd, naive.time()))
                else:
                    try: out.append(naive.replace(year=y, month=m))
                    except ValueError: pass
                yield sorted(out)
                k += 1
        elif freq == "YEARLY":
            k = 0
            while True:
                try: yield [naive.replace(year=naive.year + k * interval)]
                except ValueError: yield []
                k += 1
        else:
            yield [naive]
            return

    for batch in candidates():
        for nv in batch:
            if nv < naive:
                continue
            occ = emit(nv)
            if until and occ > until:
                return
            if count is not None and produced >= count:
                return
            produced += 1
            yield occ
        if batch and emit(batch[-1]) > window_end:
            return
        if produced > 20000:
            return


def main():
    now = datetime.now(timezone.utc)
    lo, hi = now - timedelta(hours=1), now + timedelta(hours=24)
    out = []
    for src in read_sources():
        try:
            events = parse_events(fetch(src))
        except Exception as e:
            print(f"island-calendar: {src[:40]}…: {e}", file=sys.stderr)
            continue
        overrides = {}
        for ev in events:
            if "RECURRENCE-ID" in ev and isinstance(ev["RECURRENCE-ID"][0], datetime):
                overrides.setdefault(ev.get("UID"), set()).add(ev["RECURRENCE-ID"][0].astimezone(timezone.utc))
        for ev in events:
            if ev.get("STATUS") == "CANCELLED" or "DTSTART" not in ev:
                continue
            start, tz = ev["DTSTART"]
            if not isinstance(start, datetime):
                continue  # día completo
            if "DTEND" in ev and isinstance(ev["DTEND"][0], datetime):
                dur = ev["DTEND"][0] - start
            elif "DURATION" in ev:
                dur = parse_duration(ev["DURATION"])
            else:
                dur = timedelta(0)
            if "RRULE" in ev and "RECURRENCE-ID" not in ev:
                skip = ev["exdates"] | overrides.get(ev.get("UID"), set())
                starts = [o for o in occurrences(start, tz, ev["RRULE"], hi)
                          if o.astimezone(timezone.utc) not in skip]
            else:
                starts = [start]
            for s in starts:
                if lo <= s <= hi:
                    out.append({"title": ev.get("title", "(No title)"),
                                "start": int(s.timestamp() * 1000),
                                "end": int((s + dur).timestamp() * 1000)})
    out.sort(key=lambda e: e["start"])
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
