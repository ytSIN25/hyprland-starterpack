import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Abre el panel de logs. Punto rojo si la última sesión acabó mal y no se ha visto.
IconPill {
    id: root
    interactive: true
    active: Globals.logsOpen
    icon: "\u{f0a2e}"   // md-bug_check
    iconColor: CrashLog.hasUnseen ? Theme.red : Theme.fgDim
    badgeCount: CrashLog.hasUnseen ? 1 : 0
    badgeColor: Theme.red
    onClicked: Globals.toggleLogs()
}
