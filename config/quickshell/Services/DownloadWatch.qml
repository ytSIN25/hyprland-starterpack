pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Descargas en curso: mira la carpeta de descargas cada 1,5 s buscando los
// ficheros temporales de los navegadores (.crdownload de Brave/Chrome, .part
// de Firefox/yt-dlp/wget). De su tamaño saca la velocidad. Cuando el temporal
// desaparece y existe el fichero final, emits finished(); si no existe, se
// canceló. Los navegadores no dicen el tamaño total, así que no hay %.
Singleton {
    id: root

    signal finished(string path)

    // [{ path, name, bytes, speed (B/s) }]
    property var active: []
    readonly property bool busy: active.length > 0
    readonly property real totalSpeed: active.reduce((a, d) => a + d.speed, 0)
    property var _prev: ({})            // path → { bytes, t, speed }

    readonly property string dir: Quickshell.env("HOME") + "/Downloads"

    // "Unconfirmed 123.crdownload" → aún sin nombre; si no, se quita la extensión temporal.
    function displayName(path) {
        const base = path.split("/").pop()
        if (/^Unconfirmed \d+\.crdownload$/.test(base)) return "…"
        return base.replace(/\.(crdownload|part|download)$/, "")
    }
    function human(b) {
        const u = ["B", "KB", "MB", "GB"]
        let i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i >= 2 ? b.toFixed(1) : Math.round(b)) + " " + u[i]
    }

    // Lista los temporales y, para los que ya no están, si existe el final.
    Process {
        id: poll
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now()
                const prev = root._prev, next = {}, list = []
                for (const l of (this.text || "").split("\n")) {
                    const f = l.split("\t")
                    if (f[0] === "tmp" && f.length >= 3) {
                        const path = f[2], bytes = parseFloat(f[1]) || 0
                        const p = prev[path]
                        let speed = 0
                        if (p && now > p.t) speed = Math.max(0, (bytes - p.bytes) * 1000 / (now - p.t))
                        // Media suave para que la cifra no baile.
                        if (p) speed = p.speed * 0.6 + speed * 0.4
                        next[path] = { bytes: bytes, t: now, speed: speed }
                        list.push({ path: path, name: root.displayName(path), bytes: bytes, speed: speed })
                    } else if (f[0] === "done" && f.length >= 2) {
                        root.finished(f[1])
                    }
                }
                root._prev = next
                root.active = list
            }
        }
    }
    Timer {
        interval: 1500
        running: true
        repeat: true
        onTriggered: {
            if (poll.running) return
            const gone = Object.keys(root._prev)
            poll.command = ["sh", "-c",
                'find "$1" -maxdepth 1 -type f \\( -name "*.crdownload" -o -name "*.part" -o -name "*.download" \\) '
                + '-printf "tmp\\t%s\\t%p\\n" 2>/dev/null; shift; '
                + 'for p in "$@"; do [ -e "$p" ] && continue; '
                + 'f="${p%.crdownload}"; f="${f%.part}"; f="${f%.download}"; '
                + '[ -s "$f" ] && printf "done\\t%s\\n" "$f"; done',
                "sh", root.dir].concat(gone)
            poll.running = true
        }
    }
}
