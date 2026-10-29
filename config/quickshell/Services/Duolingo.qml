pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Config

// Progreso real de Duolingo vía la API pública de perfiles (sin login):
// racha, XP total, curso actual y si ya se practicó hoy. El usuario se lee
// de ~/.local/state/quickshell/duolingo-user (una línea con el username).
Singleton {
    id: root

    readonly property string userFile: Settings.home + "/.local/state/quickshell/duolingo-user"
    property string username: ""
    property bool   ok: false
    property int    streak: 0
    property int    totalXp: 0
    property string course: ""
    property int    courseXp: 0
    property string streakEnd: ""
    readonly property bool practicedToday: ok && streakEnd === Qt.formatDate(new Date(), "yyyy-MM-dd")

    // Panel visible = special:duolingo activo en algún monitor (evento de Hyprland).
    property bool panelOpen: false
    function toggle() {
        Quickshell.execDetached([Settings.home + "/.config/quickshell/scripts/duolingo-toggle.sh"])
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name !== "activespecial") return
            const open = ev.data.startsWith("special:duolingo,")
            // Al cerrar el panel, refresca la racha (acabas de practicar).
            if (root.panelOpen && !open) refreshDelay.restart()
            root.panelOpen = open
        }
    }
    Timer { id: refreshDelay; interval: 3000; onTriggered: root.refresh() }
    function refresh() { if (username !== "" && !proc.running) proc.running = true }

    FileView {
        path: root.userFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.username = text().trim(); root.refresh() }
        onLoadFailed: root.username = ""
    }

    Process {
        id: proc
        command: ["curl", "-sf", "--compressed", "--max-time", "8", "-A", "Mozilla/5.0",
                  "https://www.duolingo.com/2017-06-30/users?username=" + encodeURIComponent(root.username)]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const u = JSON.parse(text).users[0]
                    root.streak = u.streak || 0
                    root.totalXp = u.totalXp || 0
                    const cs = u.streakData && u.streakData.currentStreak
                    root.streakEnd = cs ? cs.endDate : ""
                    const c = (u.courses || []).find(c => c.id === u.currentCourseId) || (u.courses || [])[0]
                    root.course = c ? c.title : ""
                    root.courseXp = c ? c.xp : 0
                    root.ok = true
                } catch (e) { root.ok = false }
            }
        }
    }

    // Cada 10 min; tras practicar, un clic derecho refresca al momento.
    Timer { interval: 600000; running: true; repeat: true; onTriggered: root.refresh() }
}
