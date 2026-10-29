import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Privacy indicator: only visible while an app uses the camera (green) or the
// microphone (orange; dimmed + slashed when the mic is muted).
// Click opens PrivacyPanel (which apps, mute mic, force quit).
Pill {
    id: root
    visible: Settings.showPrivacy && Privacy.active
    interactive: true
    active: Globals.privacyOpen
    spacing: Theme.space4
    onClicked: Globals.togglePrivacy()

    Text {
        visible: Privacy.cameraInUse
        text: "\u{f0100}"   // camera
        color: Theme.green
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    Text {
        visible: Privacy.micInUse
        text: Privacy.micMuted ? "\u{f036d}" : "\u{f036c}"   // microphone-off / microphone
        color: Privacy.micMuted ? Theme.fgMuted : Theme.orange
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }

    // Gentle pulse so it catches the eye when something starts recording.
    SequentialAnimation on opacity {
        running: root.visible && !Privacy.micMuted
        loops: 3
        alwaysRunToEnd: true
        NumberAnimation { to: 0.4; duration: 400; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutSine }
    }
}
