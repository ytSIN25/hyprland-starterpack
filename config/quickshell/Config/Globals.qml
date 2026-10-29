pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Estado global compartido. Un único panel abierto a la vez.
Singleton {
    id: g

    // "", "control", "notif", "sysmon", "launcher", "clipboard", "dashboard", "capture", "gpu", "updates", "ai-usage", "battery", "firewall", "privacy", "disk", "logs"
    property string openPanel: ""
    // Iconos ocultos de la barra (p. ej. Duolingo): se muestran/ocultan con
    // SUPER+SHIFT+D (qs ipc call panel hidden). No persiste: arranca oculto.
    property bool showHiddenIcons: false

    property string openedOnMonitor: ""

    property bool settingsOpen: false

    property bool dnd: false

    readonly property bool controlCenterOpen: openPanel === "control"
    readonly property bool notifCenterOpen:   openPanel === "notif"
    readonly property bool sysMonOpen:         openPanel === "sysmon"
    readonly property bool launcherOpen:       openPanel === "launcher"
    readonly property bool clipboardOpen:      openPanel === "clipboard"
    readonly property bool dashboardOpen:      openPanel === "dashboard"
    readonly property bool screenCaptureOpen:  openPanel === "capture"
    readonly property bool gpuOffloadOpen:      openPanel === "gpu"
    readonly property bool updatesOpen:         openPanel === "updates"
    readonly property bool aiUsageOpen:         openPanel === "ai-usage"
    readonly property bool batteryOpen:         openPanel === "battery"
    readonly property bool firewallOpen:        openPanel === "firewall"
    readonly property bool privacyOpen:         openPanel === "privacy"
    readonly property bool diskOpen:            openPanel === "disk"
    readonly property bool logsOpen:            openPanel === "logs"

    function open(p) {
        openedOnMonitor = Hyprland.focusedMonitor?.name ?? ""
        openPanel = p
    }
    function toggle(p)            { if (openPanel === p) openPanel = ""; else open(p) }
    function toggleControlCenter() { toggle("control") }
    function toggleNotifCenter()   { toggle("notif") }
    function toggleSysMon()        { toggle("sysmon") }
    function toggleLauncher()      { toggle("launcher") }
    function toggleClipboard()     { toggle("clipboard") }
    function toggleDashboard()     { toggle("dashboard") }
    function toggleScreenCapture()  { toggle("capture") }
    function toggleGpuOffload()    { toggle("gpu") }
    function toggleUpdates()       { toggle("updates") }
    function toggleAiUsage()       { toggle("ai-usage") }
    function toggleBattery()       { toggle("battery") }
    function toggleFirewall()      { toggle("firewall") }
    function togglePrivacy()       { toggle("privacy") }
    function toggleDisk()          { toggle("disk") }
    function toggleLogs()          { toggle("logs") }
    signal settingsResummon()
    function toggleSettings() {
        if (settingsOpen) settingsResummon()
        else settingsOpen = true
    }
    function closeAll()            { openPanel = "" }

    function runPowerAction(action) {
        closeAll()
        if (action === "lock")
            Quickshell.execDetached(["sh", "-c", "sleep 0.25; command -v hyprlock >/dev/null && hyprlock || loginctl lock-session"])
        else if (action === "suspend")
            Quickshell.execDetached(["systemctl", "suspend"])
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"])
        else if (action === "poweroff")
            Quickshell.execDetached(["systemctl", "poweroff"])
    }
}
