import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Components
import qs.Config
import qs.Services

// WiFi: cabecera con estado + interruptor y lista de redes, la conectada
// resaltada. Escanea solo mientras está visible. Click conecta/desconecta.
ColumnLayout {
    id: root
    width: parent ? parent.width : implicitWidth
    spacing: Theme.space10

    Component.onCompleted: Net.setScanning(true)
    Component.onDestruction: Net.setScanning(false)

    // Conectada primero, luego por intensidad.
    readonly property var netList: {
        const arr = (Net.networks?.values ?? []).slice()
        arr.sort((a, b) =>
            ((b.connected ? 1 : 0) - (a.connected ? 1 : 0))
            || ((b.signalStrength ?? 0) - (a.signalStrength ?? 0)))
        return arr
    }

    // IPv4 de este PC (lo que daría `ip a`): Wi-Fi/Ethernet y las redes
    // privadas (ZeroTier, Tailscale, VPN). Docker, veth y loopback fuera.
    // [{ iface, label, ip, prefix }], la de la conexión principal primero.
    property var ips: []
    property string copiedIp: ""
    function ifaceLabel(n) {
        if (/^wl/.test(n)) return I18n.tr("Wi-Fi")
        if (/^(en|eth)/.test(n)) return I18n.tr("Ethernet")
        if (/^zt/.test(n)) return "ZeroTier"
        if (/^tailscale/.test(n)) return "Tailscale"
        if (/^(tun|tap|wg|ppp)/.test(n)) return "VPN"
        return ""
    }
    Process {
        id: ipProc
        command: ["ip", "-j", "-4", "addr", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = []
                try {
                    for (const i of JSON.parse(this.text)) {
                        const label = root.ifaceLabel(i.ifname)
                        if (label === "" || i.operstate === "DOWN") continue
                        for (const a of i.addr_info || [])
                            out.push({ iface: i.ifname, label: label, ip: a.local, prefix: a.prefixlen })
                    }
                } catch (e) {}
                const rank = x => x.label === I18n.tr("Wi-Fi") || x.label === I18n.tr("Ethernet") ? 0 : 1
                out.sort((a, b) => rank(a) - rank(b))
                root.ips = out
            }
        }
    }
    // Mientras la pestaña está abierta; cambia al moverse de red o con la VPN.
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!ipProc.running) ipProc.running = true
    }
    Timer {
        id: copiedReset
        interval: 1500
        onTriggered: root.copiedIp = ""
    }

    // Caja única.
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

            // Cabecera: icono + estado + spinner de escaneo + interruptor.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Text {
                    text: Net.icon
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                }
                Text {
                    Layout.fillWidth: true
                    text: !Net.wifiEnabled ? I18n.tr("WiFi disabled")
                        : Net.ssid !== "" ? I18n.tr("Connected to %1").arg(Net.ssid)
                        : Net.scanning ? I18n.tr("Searching networks...")
                        : I18n.tr("WiFi enabled")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    visible: Net.wifiEnabled && Net.scanning
                    text: "󰑮"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1200
                        loops: Animation.Infinite; running: parent.visible
                    }
                }
                // Engranaje: ajustes IP de la conexión activa (wifi/ethernet).
                Text {
                    visible: Net.online
                    text: "󰒓"
                    color: gearMa.containsMouse ? Theme.accent : Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 1
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    MouseArea {
                        id: gearMa
                        anchors.fill: parent
                        anchors.margins: -Theme.space4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Net.openIpConfig()
                    }
                }
                Switch {
                    checked: Net.wifiEnabled
                    onToggled: Net.toggleWifi()
                }
            }

            // IP de este PC: una pastilla por interfaz, clic = copiar.
            RowLayout {
                Layout.fillWidth: true
                visible: root.ips.length > 0
                spacing: Theme.space8
                Text {
                    Layout.alignment: Qt.AlignTop
                    text: "󰩟"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space4
                    Text {
                        text: I18n.tr("IP address")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.space6
                        Repeater {
                            model: root.ips
                            Rectangle {
                                id: ipChip
                                required property var modelData
                                readonly property bool copied: root.copiedIp === modelData.ip
                                width: ipRow.implicitWidth + Theme.space12
                                height: ipRow.implicitHeight + Theme.space6
                                radius: height / 2
                                color: ipMa.containsMouse ? Theme.withAlpha(Theme.overlay, 0.4) : Theme.withAlpha(Theme.overlay, 0.18)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Row {
                                    id: ipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.space6
                                    Text {
                                        text: ipChip.modelData.label
                                        color: Theme.fgMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                    }
                                    Text {
                                        text: ipChip.copied ? I18n.tr("Copied") : ipChip.modelData.ip
                                        color: ipChip.copied ? Theme.green : Theme.fg
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                        font.bold: true
                                    }
                                }
                                MouseArea {
                                    id: ipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Quickshell.execDetached(["wl-copy", ipChip.modelData.ip])
                                        root.copiedIp = ipChip.modelData.ip
                                        copiedReset.restart()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // MAC privada de la red conectada (Services/MacPrivacy.qml).
            RowLayout {
                Layout.fillWidth: true
                visible: Net.wifiEnabled && Net.ssid !== "" && MacPrivacy.uuid !== ""
                spacing: Theme.space8
                Text {
                    text: "󰒃"
                    color: MacPrivacy.mode === "off" ? Theme.fgMuted : Theme.green
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.tr("Private MAC address")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        Layout.fillWidth: true
                        text: MacPrivacy.busy ? I18n.tr("Reconnecting...")
                            : MacPrivacy.address + (MacPrivacy.randomized ? "  · " + I18n.tr("randomized") : "  · " + I18n.tr("real"))
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideRight
                    }
                }
                // Selector Off / Stable / Random.
                Row {
                    spacing: Theme.space2
                    opacity: MacPrivacy.busy ? 0.5 : 1
                    Repeater {
                        model: [
                            { v: "off",    t: I18n.tr("Off") },
                            { v: "stable", t: I18n.tr("Stable") },
                            { v: "random", t: I18n.tr("Random") }
                        ]
                        Rectangle {
                            required property var modelData
                            readonly property bool sel: MacPrivacy.mode === modelData.v
                            width: segText.implicitWidth + Theme.space12
                            height: segText.implicitHeight + Theme.space6
                            radius: height / 2
                            color: sel ? Theme.accent : segMa.containsMouse ? Theme.withAlpha(Theme.overlay, 0.4) : Theme.withAlpha(Theme.overlay, 0.18)
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Text {
                                id: segText
                                anchors.centerIn: parent
                                text: modelData.t
                                color: parent.sel ? Theme.bg : Theme.fgDim
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                font.bold: parent.sel
                            }
                            MouseArea {
                                id: segMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MacPrivacy.setMode(modelData.v)
                            }
                        }
                    }
                }
            }

            // Estado vacío.
            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                Layout.bottomMargin: Theme.space2
                visible: Net.wifiEnabled && root.netList.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: Net.scanning ? I18n.tr("Searching networks...") : I18n.tr("No networks found")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            // Lista de redes con altura acotada y scroll; la activa queda resaltada.
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Theme.dp(248), contentHeight)
                visible: Net.wifiEnabled && root.netList.length > 0
                clip: true
                spacing: Theme.space6
                model: root.netList
                delegate: NetRow {}
            }
        }
    }

    // Fila de red sobre la DeviceRow compartida; aquí solo queda lo propio
    // del WiFi: glifo por cobertura, % y candado, y la lógica de conexión.
    component NetRow: DeviceRow {
        id: nr
        required property var modelData
        width: ListView.view ? ListView.view.width : implicitWidth

        readonly property bool conn: modelData?.connected ?? false
        readonly property bool known: modelData?.known ?? false
        readonly property int sig: Math.round((modelData?.signalStrength ?? 0) * 100)
        readonly property bool secured: (modelData?.security ?? WifiSecurityType.Open) !== WifiSecurityType.Open

        active: conn
        icon: sig >= 75 ? "󰤨" : sig >= 50 ? "󰤥" : sig >= 25 ? "󰤢" : "󰤟"
        title: modelData?.name ?? ""
        subtitle: conn ? I18n.tr("connected") : known ? I18n.tr("saved") : ""
        subtitleColor: conn ? Theme.green : Theme.fgMuted

        // % de cobertura de la red.
        Text {
            text: nr.sig + "%"
            color: nr.conn ? Theme.accent : Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
            font.bold: nr.conn
        }
        // Candado para redes protegidas.
        Text {
            visible: nr.secured
            text: "󰌾"
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        onClicked: {
            if (conn)
                modelData.disconnect()
            else if (known || !secured)
                modelData.connect()
            else
                Net.requestPassword(modelData)
        }

        // Red guardada cuyas credenciales fallan (contraseña caducada, etc.):
        // se vuelven a pedir en el modal.
        Connections {
            target: nr.modelData
            ignoreUnknownSignals: true
            function onConnectionFailed(reason) {
                if (nr.secured && Net.promptNetwork === null
                        && (reason === ConnectionFailReason.NoSecrets
                            || reason === ConnectionFailReason.WifiClientFailed
                            || reason === ConnectionFailReason.WifiAuthTimeout))
                    Net.requestPassword(nr.modelData)
            }
        }
    }
}
