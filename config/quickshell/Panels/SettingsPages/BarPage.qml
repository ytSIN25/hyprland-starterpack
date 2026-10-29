import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services
import qs.Panels.SettingsPages

// Barra
ColumnLayout {
    spacing: Theme.space14

    // Estilo visual de la barra: píldoras separadas o tira continua.
    SettingsCard {
        title: I18n.tr("Bar style"); glyph: "󰝚"
        SwitchRow { skey: "barSeparated"; label: I18n.tr("Separated widgets"); checked: Settings.barSeparated
            onToggled: Settings.barSeparated = !Settings.barSeparated }
    }

    // Widgets de la barra, agrupados en una tarjeta.
    SettingsCard {
        title: I18n.tr("Visible widgets"); glyph: "󰕬"
        Text {
            Layout.fillWidth: true
            text: I18n.tr("Hidden widgets only appear when you press Super+Shift+D.")
            color: Theme.fgMuted
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
            wrapMode: Text.WordWrap
        }
        SwitchRow { skey: "showMedia"; label: I18n.tr("Media player"); checked: Settings.showMedia
            onToggled: Settings.showMedia = !Settings.showMedia }
        SwitchRow { skey: "showTray"; hideKey: "tray"; label: I18n.tr("System tray"); checked: Settings.showTray
            onToggled: Settings.showTray = !Settings.showTray }
        SwitchRow { skey: "showSysmon"; hideKey: "sysmon"; label: I18n.tr("Resource monitor"); checked: Settings.showSysmon
            onToggled: Settings.showSysmon = !Settings.showSysmon }
        SwitchRow { skey: "showBattery"; hideKey: "battery"; label: I18n.tr("Battery"); shown: SettingsPalette.hasBattery
            checked: Settings.showBattery
            onToggled: Settings.showBattery = !Settings.showBattery }
        // Solo si está instalado power-profiles-daemon.
        SwitchRow { skey: "showPowerProfile"; hideKey: "power"; label: I18n.tr("Power profile"); shown: Power.available
            checked: Settings.showPowerProfile
            onToggled: Settings.showPowerProfile = !Settings.showPowerProfile }
        SwitchRow { skey: "showClipboard"; hideKey: "clipboard"; label: I18n.tr("Clipboard"); checked: Settings.showClipboard
            onToggled: Settings.showClipboard = !Settings.showClipboard }
        SwitchRow { skey: "showNotifications"; hideKey: "notifications"; label: I18n.tr("Notifications"); checked: Settings.showNotifications
            onToggled: Settings.showNotifications = !Settings.showNotifications }
        SwitchRow { skey: "showCaffeine"; hideKey: "caffeine"; label: I18n.tr("Caffeine"); checked: Settings.showCaffeine
            onToggled: Settings.showCaffeine = !Settings.showCaffeine }
        SwitchRow { skey: "showGpuOffload"; hideKey: "gpuOffload"; label: I18n.tr("GPU offload"); checked: Settings.showGpuOffload
            onToggled: Settings.showGpuOffload = !Settings.showGpuOffload }
        SwitchRow { skey: "showUpdates"; hideKey: "updates"; label: I18n.tr("Updates"); checked: Settings.showUpdates
            onToggled: Settings.showUpdates = !Settings.showUpdates }
        SwitchRow { skey: "showDiskClean"; hideKey: "diskClean"; label: I18n.tr("Disk cleaner"); checked: Settings.showDiskClean
            onToggled: Settings.showDiskClean = !Settings.showDiskClean }
        SwitchRow { skey: "showLogs"; hideKey: "logs"; label: I18n.tr("System logs"); checked: Settings.showLogs
            onToggled: Settings.showLogs = !Settings.showLogs }
        SwitchRow { skey: "showLauncher"; hideKey: "launcher"; label: I18n.tr("Launcher"); checked: Settings.showLauncher
            onToggled: Settings.showLauncher = !Settings.showLauncher }
        SwitchRow { skey: "showWorkspaces"; hideKey: "workspaces"; label: I18n.tr("Workspaces"); checked: Settings.showWorkspaces
            onToggled: Settings.showWorkspaces = !Settings.showWorkspaces }
        SwitchRow { skey: "showActiveWindow"; hideKey: "activeWindow"; label: I18n.tr("Active window"); checked: Settings.showActiveWindow
            onToggled: Settings.showActiveWindow = !Settings.showActiveWindow }
        SwitchRow { skey: "showConnectivity"; hideKey: "connectivity"; label: I18n.tr("Wi-Fi, Bluetooth & audio"); checked: Settings.showConnectivity
            onToggled: Settings.showConnectivity = !Settings.showConnectivity }
        SwitchRow { skey: "showVpn"; hideKey: "vpn"; label: I18n.tr("VPN"); checked: Settings.showVpn
            onToggled: Settings.showVpn = !Settings.showVpn }
        SwitchRow { skey: "showPrivacy"; hideKey: "privacy"; label: I18n.tr("Privacy indicator"); checked: Settings.showPrivacy
            onToggled: Settings.showPrivacy = !Settings.showPrivacy }
        SwitchRow { skey: "showWazuh"; hideKey: "wazuh"; label: I18n.tr("Wazuh"); checked: Settings.showWazuh
            onToggled: Settings.showWazuh = !Settings.showWazuh }
        SwitchRow { skey: "showFirewall"; hideKey: "firewall"; label: I18n.tr("Firewall"); checked: Settings.showFirewall
            onToggled: Settings.showFirewall = !Settings.showFirewall }
        SwitchRow { skey: "showAiUsage"; hideKey: "aiUsage"; label: I18n.tr("AI usage"); checked: Settings.showAiUsage
            onToggled: Settings.showAiUsage = !Settings.showAiUsage }
        SwitchRow { skey: "showDuolingo"; hideKey: "duolingo"; label: I18n.tr("Duolingo"); checked: Settings.showDuolingo
            onToggled: Settings.showDuolingo = !Settings.showDuolingo }
        SwitchRow { skey: "showSshd"; hideKey: "sshd"; label: I18n.tr("SSH server"); checked: Settings.showSshd
            onToggled: Settings.showSshd = !Settings.showSshd }
        SwitchRow { skey: "showPingIp"; hideKey: "pingIp"; label: I18n.tr("Ping monitor"); checked: Settings.showPingIp
            onToggled: Settings.showPingIp = !Settings.showPingIp }
        SwitchRow { skey: "showWifiPass"; hideKey: "wifiPass"; label: I18n.tr("WiFi passwords"); checked: Settings.showWifiPass
            onToggled: Settings.showWifiPass = !Settings.showWifiPass }
        SwitchRow { skey: "showShutdown"; hideKey: "shutdown"; label: I18n.tr("Power menu"); checked: Settings.showShutdown
            onToggled: Settings.showShutdown = !Settings.showShutdown }
        SwitchRow { skey: "weatherShowInBar"; hideKey: "weather"; label: I18n.tr("Weather"); checked: Settings.weatherShowInBar
            onToggled: Settings.weatherShowInBar = !Settings.weatherShowInBar }
    }
}
