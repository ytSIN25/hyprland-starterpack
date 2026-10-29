import QtQuick
import QtQuick.Layouts
import qs.Config
import qs.Services

// Una columna de la hora de la alarma (field "h" o "m"): flechas, rueda
// (Mayús = ±5) o escribir el número. Da la vuelta (59 → 00).
ColumnLayout {
    id: spin
    property string field: "h"
    readonly property bool isH: field === "h"
    readonly property int value: Island.alarmEdit ? Island.alarmEdit[field] : 0
    readonly property int shown: isH && !Settings.clock24h ? ((value % 12) || 12) : value
    readonly property string shownText: (shown < 10 ? "0" : "") + shown
    function step(d) {
        if (!Island.alarmEdit) return
        if (isH) Island.setAlarmEdit({ h: (value + d + 24) % 24 })
        else Island.setAlarmEdit({ m: ((value + d) % 60 + 60) % 60 })
    }
    spacing: 0

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (ev) => spin.step((ev.angleDelta.y > 0 ? 1 : -1) * ((ev.modifiers & Qt.ShiftModifier) ? 5 : 1))
    }
    Repeater {
        model: [1, 0, -1]               // ▲ · número · ▼
        Item {
            id: cell
            required property int modelData
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Theme.dp(58)
            implicitHeight: modelData === 0 ? Theme.dp(42) : Theme.dp(18)
            Text {
                visible: cell.modelData !== 0
                anchors.centerIn: parent
                text: cell.modelData > 0 ? "\u{f0143}" : "\u{f0140}"
                color: arrowMa.containsMouse ? "white" : Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.dp(18)
                MouseArea {
                    id: arrowMa
                    anchors.fill: parent
                    anchors.margins: -Theme.dp(6)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: spin.step(cell.modelData)
                    // Mantener pulsado = repetir
                    onPressAndHold: repeat.start()
                    onReleased: repeat.stop()
                    Timer { id: repeat; interval: 90; repeat: true; onTriggered: spin.step(cell.modelData) }
                }
            }
            Rectangle {
                visible: cell.modelData === 0
                anchors.fill: parent
                radius: Theme.dp(10)
                color: num.activeFocus ? Theme.withAlpha(Theme.magenta, 0.2) : "transparent"
                TextInput {
                    id: num
                    anchors.centerIn: parent
                    text: spin.shownText
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(34)
                    font.bold: true
                    font.features: { "tnum": 1 }
                    maximumLength: 2
                    validator: IntValidator { bottom: 0; top: 59 }
                    selectByMouse: true
                    selectionColor: Theme.withAlpha(Theme.magenta, 0.5)
                    onActiveFocusChanged: if (activeFocus) selectAll()
                    onEditingFinished: apply()
                    Keys.onUpPressed: spin.step(1)
                    Keys.onDownPressed: spin.step(-1)
                    Keys.onEscapePressed: Island.alarmEdit = null
                    function apply() {
                        let v = parseInt(text)
                        if (!isNaN(v) && Island.alarmEdit) {
                            if (!spin.isH) Island.setAlarmEdit({ m: Math.min(59, v) })
                            else if (Settings.clock24h) Island.setAlarmEdit({ h: Math.min(23, v) })
                            else Island.setAlarmEdit({ h: Math.max(1, Math.min(12, v)) % 12 + (spin.value >= 12 ? 12 : 0) })
                        }
                        text = Qt.binding(() => spin.shownText)
                    }
                }
            }
        }
    }
}
