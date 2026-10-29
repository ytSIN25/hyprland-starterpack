import QtQuick
import QtQuick.Effects

// Image clipped to a rounded rectangle (Qt6 has no `clip` for radii).
Item {
    id: root
    property alias source: img.source
    property alias status: img.status
    property real radius: 0

    Image {
        id: img
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        mipmap: true
        visible: false
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        layer.enabled: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        visible: img.status === Image.Ready
    }
}
