import QtQuick
import qs.Config

// Claude's sunburst: rays through the centre (AiUsagePanel).
Item {
    id: mark
    property real size: Theme.dp(18)
    property color color: "#d97757"
    implicitWidth: size; implicitHeight: size
    Repeater {
        model: 8
        Rectangle {
            required property int index
            anchors.centerIn: parent
            width: mark.size * 0.13; height: mark.size
            radius: width / 2
            color: mark.color
            rotation: index * 22.5
        }
    }
}
