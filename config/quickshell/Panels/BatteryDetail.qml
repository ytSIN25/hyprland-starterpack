import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Components
import qs.Config
import qs.Services

// Detalle de batería: cabecera con estado + %, barra de progreso, info de
// tamaño/ciclos/tiempo restante (vía `upower -i`, ya que esas propiedades no
// están expuestas de forma fiable por el binding de UPower en QML), y el
// selector de perfil de energía reutilizado tal cual de PowerDetail.qml.
Popout {
    id: panel
    ns: "qs-battery"
    cardWidth: 380
    cardMinWidth: 320
    scrollable: false
    shown: Globals.batteryOpen

    onShownChanged: if (shown) fetchProc.running = true

    readonly property var dev: {
        const devices = UPower.devices ?? []
        for (let i = 0; i < devices.length; i++) {
            const d = devices[i]
            if (d && ((d.type === "Battery") || (d.isLaptopBattery ?? false)))
                return d
        }
        return UPower.displayDevice
    }
    readonly property int percent: Math.max(0, Math.min(100, Math.round((dev?.percentage ?? 0) * 100)))
    readonly property bool charging: (dev?.state ?? 0) === UPowerDeviceState.Charging
                                     || (dev?.state ?? 0) === UPowerDeviceState.PendingCharge
    readonly property bool fullyCharged: (dev?.state ?? 0) === UPowerDeviceState.FullyCharged
    readonly property string statusLabel:
        fullyCharged ? I18n.tr("FULLY CHARGED")
        : charging ? I18n.tr("CHARGING")
        : I18n.tr("DISCHARGING")

    // Datos que `upower -i` da y el binding QML no expone de forma fiable.
    property string sizeWh: "-"
    property string cycles: "-"
    property string timeToFull: "-"
    property string timeToEmpty: "-"

    Process {
        id: fetchProc
        command: ["sh", "-c", "upower -i $(upower -e | grep -i battery | head -n1) 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n")
                for (const raw of lines) {
                    const line = raw.trim()
                    if (line.indexOf("energy-full:") === 0)
                        panel.sizeWh = line.split(":")[1].trim().replace(" Wh", "Wh")
                    else if (line.indexOf("charge-cycles:") === 0)
                        panel.cycles = line.split(":")[1].trim()
                    else if (line.indexOf("time to full:") === 0)
                        panel.timeToFull = line.split(":").slice(1).join(":").trim()
                    else if (line.indexOf("time to empty:") === 0)
                        panel.timeToEmpty = line.split(":").slice(1).join(":").trim()
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + Theme.space16 * 2
        radius: Theme.barRadius
        color: Theme.withAlpha(Theme.surface, 0.62)
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.34)

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.space14
            spacing: Theme.space10

            // Cabecera: icono + "Battery" + estado, % grande a la derecha.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                // Icono dibujado (rectángulos), no depende de que la fuente
                // tenga el glifo — el mismo problema que ya tuvo el icono
                // del pill de la barra.
                Item {
                    implicitWidth: Theme.dp(24)
                    implicitHeight: Theme.dp(14)
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: battBody
                        width: parent.width - Theme.dp(3)
                        height: parent.height
                        radius: Theme.dp(3)
                        color: "transparent"
                        border.width: Theme.dp(1.5)
                        border.color: Theme.fg
                    }
                    Rectangle {
                        anchors.left: battBody.right
                        anchors.verticalCenter: battBody.verticalCenter
                        width: Theme.dp(3)
                        height: Theme.dp(6)
                        radius: Theme.dp(1)
                        color: Theme.fg
                    }
                    Rectangle {
                        anchors.left: battBody.left
                        anchors.verticalCenter: battBody.verticalCenter
                        anchors.leftMargin: Theme.dp(2)
                        height: battBody.height - Theme.dp(4)
                        width: Math.max(Theme.dp(2), (battBody.width - Theme.dp(4)) * panel.percent / 100)
                        radius: Theme.dp(1)
                        color: panel.charging ? Theme.cyan : Theme.fg
                        Behavior on width { NumberAnimation { duration: Theme.animFast } }
                    }
                    // Rayo pequeño en la esquina si está cargando — decorativo,
                    // no crítico si el glifo no existe en la fuente.
                    Text {
                        visible: panel.charging
                        anchors.centerIn: parent
                        text: "\u26A1"
                        color: Theme.cyan
                        font.pixelSize: Theme.dp(11)
                        style: Text.Outline
                        styleColor: Theme.surface
                    }
                }

                ColumnLayout {
                    spacing: 0
                    Text {
                        text: I18n.tr("Battery")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                    }
                    Text {
                        text: panel.statusLabel
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 4
                        font.bold: true
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: panel.percent + "%"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 10
                    font.bold: true
                }
            }

            // Barra de progreso.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.dp(8)
                radius: height / 2
                color: Theme.withAlpha(Theme.overlay, 0.35)

                Rectangle {
                    height: parent.height
                    width: parent.width * panel.percent / 100
                    radius: height / 2
                    color: Theme.fg
                    Behavior on width { NumberAnimation { duration: Theme.animFast } }
                }
            }

            // Rejilla de info: tamaño/ciclos a la izquierda, tiempos a la derecha.
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.space16
                rowSpacing: Theme.space4

                InfoRow { label: I18n.tr("Battery size"); value: panel.sizeWh }
                InfoRow { label: I18n.tr("Time to full"); value: panel.charging ? panel.timeToFull : "-" }
                InfoRow { label: I18n.tr("Charge cycles"); value: panel.cycles }
                InfoRow { label: I18n.tr("Charging"); value: panel.charging ? I18n.tr("Yes") : "-" }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.hairline
                color: Theme.withAlpha(Theme.overlay, 0.28)
            }

            Text {
                text: I18n.tr("POWER PROFILE")
                color: Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
                font.bold: true
            }

            // Mismas filas de perfil que PowerDetail.qml, reutilizadas tal cual.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space6
                Repeater {
                    model: Power.profiles
                    delegate: ProfileRow {
                        required property var modelData
                        info: modelData
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.hairline
                color: Theme.withAlpha(Theme.overlay, 0.28)
            }

            // Fan curve, Lenovo Vantage "Fan Speed Custom" style: one vertical
            // slider per temperature step. Hardware I/O goes through the root
            // helper (scripts/quickshell-fan-curve, LenovoLegionLinux backend).
            ColumnLayout {
                id: fanControl
                Layout.fillWidth: true
                spacing: Theme.space8

                // Legion fan table rows: { fan1_speed, fan2_speed, cpu_lower_temp, ... }
                property var entries: []
                property bool dirty: false
                property bool busy: false
                property bool backendOk: false
                property string status: ""
                property int hovered: -1
                readonly property int maxRpm: 5000
                readonly property string helper: "/usr/local/sbin/quickshell-fan-curve"
                readonly property string baseFile: Quickshell.env("HOME") + "/.config/quickshell/fan-curve-base.yaml"

                // Sets both fans of step i and keeps the curve non-decreasing,
                // which the firmware expects. This EC forces fan 2 to fan 1's
                // speed, so a different fan 2 value is rejected on Apply.
                function setSpeed(i, rpm) {
                    rpm = Math.round(Math.max(0, Math.min(maxRpm, rpm)) / 100) * 100
                    const pts = entries.map(e => Object.assign({}, e))
                    function put(j, v) {
                        pts[j].fan1_speed = v
                        pts[j].fan2_speed = v
                    }
                    put(i, rpm)
                    for (let j = i + 1; j < pts.length; j++) if (pts[j].fan1_speed < rpm) put(j, rpm)
                    for (let j = 0; j < i; j++) if (pts[j].fan1_speed > rpm) put(j, rpm)
                    entries = pts
                    dirty = true
                }

                // Minimal reader for legion_cli's fan curve YAML (fan-curve-base.yaml).
                function parseYaml(text) {
                    const out = []
                    let cur = null
                    for (const raw of (text || "").split("\n")) {
                        const m = raw.match(/^\s*(-\s+)?(\w+):\s*(\S+)\s*$/)
                        if (!m) continue
                        if (m[1]) { cur = {}; out.push(cur) }
                        else if (!/^\s/.test(raw)) { cur = null; continue }
                        if (cur) cur[m[2]] = Number(m[3])
                    }
                    return out
                }

                function load() {
                    status = "Reading fan curve…"
                    readProc.running = true
                }
                function apply() {
                    busy = true
                    status = "Applying…"
                    // The EC overwrites fan 2 with fan 1's speed, so send them equal
                    // (the base/stock tables have fan 2 300 RPM higher).
                    entries = entries.map(e => Object.assign({}, e, { fan2_speed: e.fan1_speed }))
                    applyProc.command = ["sudo", "-n", helper, "apply", JSON.stringify(entries)]
                    applyProc.running = true
                }
                function resetToBase() {
                    baseProc.applyAfter = backendOk
                    baseProc.running = true
                }

                // Hardware first; if the backend isn't set up, show the saved base curve.
                Process {
                    id: readProc
                    command: ["sudo", "-n", fanControl.helper, "read"]
                    stdout: StdioCollector { id: readOut }
                    stderr: StdioCollector { id: readErr }
                    onExited: (code) => {
                        if (code === 0) {
                            try {
                                fanControl.entries = JSON.parse(readOut.text)
                                fanControl.backendOk = true
                                fanControl.dirty = false
                                fanControl.status = ""
                                return
                            } catch (e) {}
                        }
                        fanControl.backendOk = false
                        baseProc.applyAfter = false
                        baseProc.running = true
                    }
                }

                Process {
                    id: baseProc
                    property bool applyAfter: false
                    command: ["cat", fanControl.baseFile]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            fanControl.entries = fanControl.parseYaml(this.text)
                            if (baseProc.applyAfter) {
                                fanControl.apply()
                            } else if (!fanControl.backendOk) {
                                fanControl.status = "Fan control not set up — showing your saved curve. Run scripts/setup-fan-power.sh."
                            }
                        }
                    }
                }

                Process {
                    id: applyProc
                    stderr: StdioCollector { id: applyErr }
                    onExited: (code) => {
                        fanControl.busy = false
                        if (code === 0) {
                            fanControl.dirty = false
                            fanControl.status = "Applied"
                        } else {
                            fanControl.status = (applyErr.text || "").trim() || "Apply failed"
                        }
                    }
                }

                Connections {
                    target: panel
                    function onShownChanged() { if (panel.shown) fanControl.load() }
                }
                Component.onCompleted: load()

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.tr("Fan Speed Custom")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Text {
                        text: I18n.tr("Adjust the fan speed in different temperature ranges")
                        color: Theme.fgDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }
                }

                Item {
                    id: curveArea
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space4
                    implicitHeight: Theme.dp(160)

                    Row {
                        id: sliderRow
                        anchors.fill: parent

                        Repeater {
                            model: fanControl.entries.length
                            delegate: Item {
                                id: col
                                required property int index
                                readonly property var e: fanControl.entries[index]
                                readonly property real frac: Math.min(1, (e ? e.fan1_speed : 0) / fanControl.maxRpm)
                                readonly property bool lit: fanControl.hovered === index
                                width: sliderRow.width / Math.max(1, fanControl.entries.length)
                                height: sliderRow.height

                                Rectangle {
                                    id: track
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    anchors.topMargin: Theme.dp(8)
                                    anchors.bottom: tempLabel.top
                                    anchors.bottomMargin: Theme.dp(10)
                                    width: Theme.dp(4)
                                    radius: width / 2
                                    color: Theme.withAlpha(Theme.overlay, 0.35)

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: parent.height * col.frac
                                        radius: parent.radius
                                        color: Theme.accent
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: parent.height * (1 - col.frac) - height / 2
                                        width: col.lit ? Theme.dp(16) : Theme.dp(13)
                                        height: width
                                        radius: width / 2
                                        color: Theme.fg
                                        border.width: Theme.dp(2)
                                        border.color: Theme.accent
                                        Behavior on width { NumberAnimation { duration: Theme.animFast } }
                                    }
                                }

                                Text {
                                    id: tempLabel
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: col.e ? col.e.ic_upper_temp + "°" : ""
                                    color: col.lit ? Theme.fg : Theme.fgDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 4
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    function setFrom(y) {
                                        const p = mapToItem(track, 0, y).y
                                        fanControl.setSpeed(col.index, (1 - p / track.height) * fanControl.maxRpm)
                                    }
                                    onEntered: fanControl.hovered = col.index
                                    onExited: if (!pressed) fanControl.hovered = -1
                                    onPressed: (m) => setFrom(m.y)
                                    onPositionChanged: (m) => { if (pressed) setFrom(m.y) }
                                    onReleased: if (!containsMouse) fanControl.hovered = -1
                                }
                            }
                        }
                    }

                    // Hover tooltip with the full table row, like the Vantage popup.
                    Rectangle {
                        id: tip
                        readonly property var e: fanControl.hovered >= 0 ? fanControl.entries[fanControl.hovered] : null
                        readonly property real colW: curveArea.width / Math.max(1, fanControl.entries.length)
                        visible: e !== null
                        z: 10
                        width: tipText.implicitWidth + Theme.space8 * 2
                        height: tipText.implicitHeight + Theme.space6 * 2
                        x: Math.max(0, Math.min(curveArea.width - width, fanControl.hovered * colW + colW / 2 - width / 2))
                        y: curveArea.height - Theme.dp(20) - height
                        radius: Theme.dp(6)
                        color: Theme.surface
                        border.width: Theme.hairline
                        border.color: Theme.withAlpha(Theme.overlay, 0.5)

                        Text {
                            id: tipText
                            anchors.centerIn: parent
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            lineHeight: 1.15
                            text: !tip.e ? "" :
                                  "CPU temp: " + tip.e.cpu_lower_temp + "–" + tip.e.cpu_upper_temp + " °C\n" +
                                  "GPU temp: " + tip.e.gpu_lower_temp + "–" + tip.e.gpu_upper_temp + " °C\n" +
                                  "Sensor temp: " + tip.e.ic_lower_temp + "–" + tip.e.ic_upper_temp + " °C\n" +
                                  "Fan 1 speed: " + tip.e.fan1_speed + " RPM\n" +
                                  "Fan 2 speed: " + tip.e.fan2_speed + " RPM"
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: fanControl.status !== ""
                    text: fanControl.status
                    color: fanControl.status === "Applied" ? Theme.green : Theme.fgDim
                    wrapMode: Text.Wrap
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space6

                    Rectangle {
                        radius: Theme.pillRadius
                        color: resetMa.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.surface, 0.6)
                        border.width: Theme.hairline
                        border.color: Theme.withAlpha(Theme.overlay, 0.4)
                        implicitWidth: resetText.implicitWidth + Theme.space16
                        implicitHeight: Theme.rowM
                        Text { id: resetText; anchors.centerIn: parent; text: I18n.tr("Reset to default"); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2 }
                        MouseArea { id: resetMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !fanControl.busy; onClicked: fanControl.resetToBase() }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        readonly property bool can: fanControl.backendOk && fanControl.dirty && !fanControl.busy
                        radius: Theme.pillRadius
                        color: can ? Theme.withAlpha(Theme.accent, applyMa.containsMouse ? 0.4 : 0.28) : Theme.withAlpha(Theme.surface, 0.4)
                        border.width: Theme.hairline
                        border.color: can ? Theme.withAlpha(Theme.accent, 0.65) : Theme.withAlpha(Theme.overlay, 0.3)
                        implicitWidth: applyText.implicitWidth + Theme.space16 * 2
                        implicitHeight: Theme.rowM
                        Text { id: applyText; anchors.centerIn: parent; text: fanControl.busy ? I18n.tr("Applying…") : I18n.tr("Apply"); color: parent.can ? Theme.fg : Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2; font.bold: true }
                        MouseArea { id: applyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: parent.can; onClicked: fanControl.apply() }
                    }
                }
            }
        }
    }

    component InfoRow: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        spacing: Theme.space6

        Text {
            text: label
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        Item { Layout.fillWidth: true }
        Text {
            text: value
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            font.bold: true
        }
    }

    component ProfileRow: Rectangle {
        id: pr
        property var info
        readonly property bool active: Power.matches(info?.value ?? -1)

        Layout.fillWidth: true
        implicitHeight: Theme.rowL
        radius: Theme.pillRadius
        color: active ? Qt.rgba(info.color.r, info.color.g, info.color.b, 0.16)
                      : prMa.containsMouse ? Theme.surfaceHi : Theme.withAlpha(Theme.surface, 0.36)
        border.width: active ? Math.max(1, Theme.dp(2)) : Theme.hairline
        border.color: active ? info.color : Theme.withAlpha(Theme.overlay, 0.28)
        Behavior on color { ColorAnimation { duration: Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space10
            anchors.rightMargin: Theme.space10
            spacing: Theme.space8

            Text {
                text: pr.info?.icon ?? ""
                color: pr.active ? pr.info.color : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                text: pr.info?.label ?? ""
                color: pr.active ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: pr.active
                elide: Text.ElideRight
            }
            Text {
                visible: pr.active
                text: I18n.tr("Active")
                color: pr.info.color
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 4
                font.bold: true
            }
            Text {
                visible: pr.active
                text: "󰓏"
                color: pr.info.color
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
        }

        MouseArea {
            id: prMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Power.set(pr.info.value)
        }
    }
}
