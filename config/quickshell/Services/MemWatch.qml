pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Memoria casi llena: antes de que el sistema se congele, la isla pregunta si
// cerrar la app que más memoria usa (Kill / Ignore). Nunca mata nada sin
// que lo pidas.
//  - Cada 2 s lee /proc/meminfo y la presión de memoria (/proc/pressure/memory,
//    "full avg10" = % de tiempo con todo parado esperando memoria).
//  - warn: < 8 % libre (RAM + zram) o presión > 10 %; critical: < 4 % o > 40 %.
//  - "Ignore" calla el aviso 5 min (salvo que pase de warn a critical).
// La app se calcula sumando la memoria de todos sus procesos (Brave = todas
// sus pestañas). Se excluye lo que tumbaría la sesión.
Singleton {
    id: root

    signal pressure(string level, real availBytes, string app, real appBytes)

    property string level: ""           // "" | "warn" | "critical"
    property real availBytes: 0
    property real totalBytes: 0
    property real psiFull: 0
    property real _snoozeUntil: 0
    property string _snoozeLevel: ""
    readonly property var protectedApps: ["Hyprland", "quickshell", "qs", "pipewire", "wireplumber",
        "pipewire-pulse", "systemd", "dbus-broker", "dbus-daemon", "Xwayland", "start-hyprland",
        "hyprlock", "sddm", "awww-daemon", "kitty", "xdg-desktop-portal", "xdg-desktop-portal-hyprland"]

    function snooze(lvl) {
        root._snoozeUntil = Date.now() + 5 * 60 * 1000
        root._snoozeLevel = lvl
        root._asked = false      // pasado el plazo, si sigue igual, se vuelve a preguntar
    }
    // Cierra todos los procesos de la app (TERM; KILL a los 5 s si sigue).
    function kill(app) {
        if (!app || protectedApps.indexOf(app) !== -1) return
        Quickshell.execDetached(["sh", "-c",
            'pkill -TERM -u "$(id -u)" -x "$1"; sleep 5; pkill -KILL -u "$(id -u)" -x "$1"', "sh", app])
    }

    FileView { id: meminfo; path: "/proc/meminfo"; blockLoading: true; printErrors: false }
    FileView { id: psi; path: "/proc/pressure/memory"; blockLoading: true; printErrors: false }

    function _kb(txt, key) {
        const m = txt.match(new RegExp("^" + key + ":\\s+(\\d+)", "m"))
        return m ? parseFloat(m[1]) * 1024 : 0
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            meminfo.reload()
            psi.reload()
            const t = meminfo.text()
            const total = root._kb(t, "MemTotal"), avail = root._kb(t, "MemAvailable")
            const swapTotal = root._kb(t, "SwapTotal"), swapFree = root._kb(t, "SwapFree")
            const m = psi.text().match(/^full avg10=([\d.]+)/m)
            root.psiFull = m ? parseFloat(m[1]) : 0
            root.totalBytes = total + swapTotal
            root.availBytes = avail + swapFree
            const frac = root.totalBytes > 0 ? root.availBytes / root.totalBytes : 1
            const lvl = frac < 0.04 || root.psiFull > 40 ? "critical"
                      : frac < 0.08 || root.psiFull > 10 ? "warn" : ""
            const prev = root.level
            root.level = lvl
            if (lvl === "") return
            const snoozed = Date.now() < root._snoozeUntil
                            && !(lvl === "critical" && root._snoozeLevel === "warn")
            if (snoozed || (lvl === prev && root._asked)) return
            root._asked = true
            if (!top.running) top.running = true
        }
    }
    property bool _asked: false
    onLevelChanged: if (level === "") _asked = false

    // App que más memoria usa (suma por nombre de proceso, solo tuyos).
    Process {
        id: top
        command: ["sh", "-c", "ps -u \"$(id -u)\" -o comm=,rss= | awk '{m[$1]+=$2} END {for (k in m) print m[k]*1024 \"\\t\" k}' | sort -rn | head -20"]
        stdout: StdioCollector {
            onStreamFinished: {
                let app = "", bytes = 0
                for (const l of (this.text || "").split("\n")) {
                    const f = l.split("\t")
                    if (f.length < 2 || root.protectedApps.indexOf(f[1]) !== -1) continue
                    app = f[1]; bytes = parseFloat(f[0]); break
                }
                root.pressure(root.level || "warn", root.availBytes, app, bytes)
            }
        }
    }
}
