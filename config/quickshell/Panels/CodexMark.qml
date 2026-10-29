import QtQuick
import qs.Config

// Codex: three interlocking loops, a nod to the OpenAI knot (AiUsagePanel).
Item {
    id: mark
    property real size: Theme.dp(18)
    property color color: "#7b8ff7"
    implicitWidth: size; implicitHeight: size
    Repeater {
        model: 3
        Rectangle {
            required property int index
            anchors.centerIn: parent
            width: mark.size * 0.48; height: mark.size
            radius: width / 2
            color: "transparent"
            border.width: Math.max(1.5, mark.size * 0.09)
            border.color: mark.color
            rotation: index * 60
        }
    }
}
