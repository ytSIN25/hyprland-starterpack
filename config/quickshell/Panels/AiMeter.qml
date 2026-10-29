import QtQuick
import QtQuick.Layouts
import qs.Config

// One usage limit for AiUsagePanel: label, time to reset, %, bar, and a
// tick showing how much of the window has elapsed (fill ahead of it =
// burning faster than the window).
ColumnLayout {
    property string label: ""
    property real pct: 0
    property var resetEpoch: null
    property var windowSecs: null
    property color barColor: Theme.accent
    property real now: Date.now()   // ticked by the panel
    readonly property real elapsed: (resetEpoch && windowSecs)
        ? 1 - Math.min(1, Math.max(0, (resetEpoch * 1000 - now) / (windowSecs * 1000)))
        : -1
    Layout.fillWidth: true
    spacing: Theme.dp(6)

    function shortDuration(ms) {
        const mins = Math.max(0, Math.round(ms / 60000))
        const d = Math.floor(mins / 1440), h = Math.floor((mins % 1440) / 60), m = mins % 60
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.dp(8)
        Text {
            text: label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
        Text {
            visible: !!resetEpoch
            text: "󰑐 " + shortDuration(resetEpoch * 1000 - now)
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Item { Layout.fillWidth: true }
        Text {
            text: Math.round(pct) + "%"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 3
            font.bold: true
        }
    }

    Rectangle {
        id: track
        Layout.fillWidth: true
        implicitHeight: Theme.dp(10)
        radius: height / 2
        color: Theme.withAlpha(Theme.overlay, 0.35)

        Rectangle {
            height: track.height
            width: Math.max(pct > 0 ? height : 0, track.width * Math.min(Math.max(pct, 0), 100) / 100)
            radius: height / 2
            color: barColor
            Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            visible: elapsed >= 0
            x: Math.round(track.width * elapsed - width / 2)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.dp(2); height: track.height + Theme.dp(2)
            radius: width / 2
            color: Theme.fg
        }
    }
}
