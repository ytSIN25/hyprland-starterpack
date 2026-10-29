import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Firewall pill: wall-fire glyph. Green when the firewall is on, red when off,
// muted when it isn't installed. Red badge = new open ports.
// Click opens FirewallPanel (activity, who is connected, blocked traffic).
IconPill {
    id: root
    interactive: true
    active: Globals.firewallOpen
    icon: "\u{f1a11}"   // wall-fire
    iconColor: !Firewall.firewallInstalled ? Theme.fgMuted
             : Firewall.firewallOn ? Theme.green : Theme.red
    animateColor: true
    badgeCount: Firewall.newPorts.length
    badgeColor: Theme.red
    onClicked: Globals.toggleFirewall()

    SequentialAnimation on opacity {
        running: Firewall.fwBusy
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.45; duration: 450; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
    }
}
