import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Wazuh toggle: shield glyph. Off: muted. On: Wazuh blue.
// Pulses while starting/stopping (the first start can take a minute).
IconPill {
    id: root
    interactive: true
    icon: "󰕥"   // shield-check
    iconColor: Wazuh.running ? "#0A7CFF" : Theme.fgMuted
    animateColor: true
    onClicked: Wazuh.toggle()

    SequentialAnimation on opacity {
        running: Wazuh.busy
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.45; duration: 450; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
    }
}
