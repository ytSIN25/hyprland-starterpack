pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Alarmas (pestaña Alarm del selector del notch, clic derecho), como en el
// móvil: hora, días de la semana (vacío = una vez), etiqueta y on/off.
// Se guardan en ~/.local/state/quickshell/alarms.json.
//  - Cada segundo se mira si alguna alarma cae entre la comprobación anterior
//    y ahora; así, si el PC estuvo suspendido, suena al despertar (hasta 30
//    min tarde; si pasó más, se da por perdida).
//  - Las de "una vez" se apagan solas al sonar.
//  - Solo suenan con el PC encendido y el shell abierto.
Singleton {
    id: root

    signal ring(var alarm)

    // [{ id, h, m, days: [0..6] (0 = domingo; vacío = una vez), on, label }]
    property var alarms: []
    property var ringing: null          // alarma sonando ahora (o null)
    property var _snoozes: []           // [{ alarm, at (epoch ms) }]
    property real _lastCheck: Date.now()
    property bool _loaded: false

    readonly property string file: Quickshell.env("HOME") + "/.local/state/quickshell/alarms.json"
    readonly property var dayLetters: ["S", "M", "T", "W", "T", "F", "S"]
    readonly property var dayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // ── Edición ─────────────────────────────────────────────────────────────
    function add(h, m, days, label) {
        const a = { id: Date.now().toString(36), h: h, m: m, days: days || [], on: true, label: label || "" }
        _set(alarms.concat([a]))
        return a
    }
    function update(id, patch) {
        _set(alarms.map(a => a.id === id ? Object.assign({}, a, patch) : a))
    }
    function remove(id) {
        _set(alarms.filter(a => a.id !== id))
        _snoozes = _snoozes.filter(s => s.alarm.id !== id)
    }
    function toggle(id) {
        const a = alarms.find(x => x.id === id)
        if (a) update(id, { on: !a.on })
    }
    function _set(list) {
        // Ordenadas por hora, como en el móvil.
        root.alarms = list.slice().sort((a, b) => (a.h * 60 + a.m) - (b.h * 60 + b.m))
        if (_loaded) store.setText(JSON.stringify(root.alarms, null, 2))
    }

    // ── Sonando ─────────────────────────────────────────────────────────────
    function stop() { root.ringing = null }
    function snooze(min) {
        if (!ringing) return
        root._snoozes = _snoozes.concat([{ alarm: ringing, at: Date.now() + (min || 5) * 60000 }])
        root.ringing = null
    }
    function _fire(a) {
        root.ringing = a
        root.ring(a)
    }

    // ── Textos ──────────────────────────────────────────────────────────────
    function timeText(h, m, use24) {
        const pad = n => (n < 10 ? "0" : "") + n
        if (use24) return pad(h) + ":" + pad(m)
        return ((h % 12) || 12) + ":" + pad(m) + (h < 12 ? " AM" : " PM")
    }
    function daysText(days) {
        if (!days || days.length === 0) return "Once"
        if (days.length === 7) return "Every day"
        const s = days.slice().sort().join("")
        if (s === "12345") return "Weekdays"
        if (s === "06") return "Weekends"
        // Lunes primero en la lista: Mon, Wed, Fri
        return days.slice().sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7)).map(d => dayNames[d]).join(", ")
    }
    // Próxima vez que sonará (Date), o null si está apagada.
    function nextFire(a, from) {
        if (!a.on) return null
        const now = from || new Date()
        for (let i = 0; i < 8; i++) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i, a.h, a.m, 0, 0)
            if (d <= now) continue
            if (a.days.length === 0 || a.days.indexOf(d.getDay()) !== -1) return d
        }
        return null
    }
    // "in 7 h 20 min"
    function untilText(d) {
        if (!d) return ""
        const min = Math.max(1, Math.round((d - Date.now()) / 60000))
        const h = Math.floor(min / 60), m = min % 60
        if (h >= 24) return "in " + Math.floor(h / 24) + " d " + (h % 24) + " h"
        return "in " + (h > 0 ? h + " h " : "") + (m > 0 || h === 0 ? m + " min" : "")
    }
    property real _now: Date.now()      // para que "in …" se refresque
    readonly property var next: {
        _now
        let best = null, bestAt = null
        for (const a of alarms) {
            const t = nextFire(a)
            if (t && (!bestAt || t < bestAt)) { best = a; bestAt = t }
        }
        return best ? { alarm: best, at: bestAt } : null
    }

    // ── Comprobación ────────────────────────────────────────────────────────
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            const now = Date.now()
            const from = Math.max(root._lastCheck, now - 30 * 60000)
            root._lastCheck = now
            if (Math.floor(now / 60000) !== Math.floor(root._now / 60000)) root._now = now
            // Posposiciones
            const due = root._snoozes.filter(s => s.at <= now)
            if (due.length > 0) {
                root._snoozes = root._snoozes.filter(s => s.at > now)
                root._fire(due[0].alarm)
                return
            }
            for (const a of root.alarms) {
                if (!a.on) continue
                // ¿Cayó entre la comprobación anterior y ahora?
                const t = root.nextFire(a, new Date(from))
                if (t && t.getTime() <= now) {
                    if (a.days.length === 0) root.update(a.id, { on: false })
                    root._fire(a)
                    return
                }
            }
        }
    }

    FileView {
        id: store
        path: root.file
        printErrors: false
        atomicWrites: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const l = JSON.parse(text())
                if (Array.isArray(l)) root.alarms = l.filter(a => a && typeof a.h === "number" && typeof a.m === "number")
                    .map(a => ({ id: String(a.id), h: a.h, m: a.m, days: Array.isArray(a.days) ? a.days : [], on: !!a.on, label: a.label || "" }))
            } catch (e) {}
            root._loaded = true
        }
        onLoadFailed: (err) => {
            root._loaded = true
            Quickshell.execDetached(["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/quickshell"])
        }
    }
}
