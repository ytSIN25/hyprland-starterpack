#!/usr/bin/env python3
"""Informe de arranques para el panel de logs (Panels/LogsPanel.qml).

Para los últimos N arranques (journalctl --list-boots) dice cómo acabó la
sesión y qué pasó de grave, en JSON:
  [{index, id, start, end (epoch ms), status, events: [{t, kind, text}], tail: [str]}]
status:
  running  arranque actual
  clean    apagado/reinicio normal
  power    apagado con el botón de encendido (típico de un cuelgue)
  crash    el log se corta sin apagado (corte de luz, botón mantenido,
           kernel panic, cuelgue total)
Los fallos durante el propio apagado (apps que mueren al cerrarse la sesión)
no se cuentan. Sin root: el grupo wheel puede leer el journal del sistema.
"""
import glob
import json
import os
import re
import subprocess
import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 6

PATTERNS = [
    ("app", re.compile(r"Process \d+ \((.+?)\) of user \d+ terminated abnormally with signal (\d+)/(\w+)"),
     lambda m: f"{m.group(1)} crashed ({m.group(3)})"),
    ("oom", re.compile(r"Out of memory: Killed process \d+ \((.+?)\)"),
     lambda m: f"Out of memory: killed {m.group(1)}"),
    ("oom", re.compile(r"earlyoom.*(?:sending SIG\w+ to|killing) .*?\"?([\w.-]+)\"?"),
     lambda m: f"Low memory: killed {m.group(1)}"),
    ("kernel", re.compile(r"(kernel panic|Kernel panic|BUG: .*|Oops: .*|soft lockup.*|blocked for more than \d+ seconds|GPU HANG.*|gpu hang.*|NVRM: Xid.*|watchdog: (?:BUG|Watchdog detected).*)"),
     lambda m: m.group(1)[:140]),
]
# Solo el gestor del sistema (systemd[1]); los de usuario (greeter, sesiones)
# también "alcanzan Shutdown" al cerrarse.
SHUTDOWN = re.compile(r"systemd\[1\]: Reached target (Shutdown|System Power Off|System Reboot)")
POWERKEY = re.compile(r"Power key pressed")
GREP = ("terminated abnormally with signal|Out of memory: Killed|earlyoom|kernel panic|Kernel panic|BUG: |Oops: "
        "|soft lockup|blocked for more than|GPU HANG|gpu hang|Xid|watchdog: (BUG|Watchdog detected)"
        "|Reached target (Shutdown|System Power Off|System Reboot)|Power key pressed")


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=20).stdout
    except Exception:
        return ""


def boot_report(b, current):
    idx = b["index"]
    lines = run(["journalctl", "-b", str(idx), "-o", "short-unix", "--no-pager", "-q", "-g", GREP]).splitlines()
    events, shut_t, power = [], None, False
    for line in lines:
        ts, _, rest = line.partition(" ")
        try:
            t = int(float(ts) * 1000)
        except ValueError:
            continue
        msg = rest.split(": ", 1)[1] if ": " in rest else rest
        if POWERKEY.search(msg):
            power = True
            shut_t = shut_t or t
            continue
        if SHUTDOWN.search(rest):
            shut_t = shut_t or t
            continue
        for kind, rx, fmt in PATTERNS:
            m = rx.search(msg)
            if m:
                events.append({"t": t, "kind": kind, "text": fmt(m)})
                break
    if shut_t:  # lo que muere durante el apagado (o 10 s antes, al cerrar sesión) no es un fallo
        events = [e for e in events if e["t"] < shut_t - 10000]

    start, end = b["first_entry"] // 1000, b["last_entry"] // 1000
    if current:
        status = "running"
    elif power:
        status = "power"
    elif shut_t:
        status = "clean"
    else:
        status = "crash"

    # Informes de fallo de Hyprland escritos durante este arranque
    for f in glob.glob(os.path.expanduser("~/.cache/hyprland/hyprlandCrashReport*.txt")):
        mt = int(os.path.getmtime(f) * 1000)
        if start <= mt <= end + 60000:
            events.append({"t": mt, "kind": "app", "text": f"Hyprland crashed (report: {os.path.basename(f)})"})

    # Últimos mensajes antes de que acabara (útil en cuelgues)
    tail = []
    if status in ("power", "crash"):
        # Todo lo que pasó justo antes (sin el ruido periódico conocido).
        args = ["journalctl", "-b", str(idx), "-n", "150", "-o", "short", "--no-pager", "-q"]
        if shut_t:
            args += ["--until", "@" + str(shut_t // 1000)]
        noise = ("quickshell-wazuh", "session opened for user", "session closed for user", "qs-fw-drop")
        tail = [l for l in run(args).splitlines() if not any(n in l for n in noise)][-20:]

    events.sort(key=lambda e: e["t"])
    return {"index": idx, "id": b["boot_id"], "start": start, "end": end,
            "status": status, "events": events, "tail": tail}


def main():
    try:
        boots = json.loads(run(["journalctl", "--list-boots", "-o", "json", "--no-pager"]) or "[]")
    except json.JSONDecodeError:
        boots = []
    boots = boots[-N:]
    out = [boot_report(b, b["index"] == 0) for b in boots]
    out.reverse()
    print(json.dumps(out))


main()
