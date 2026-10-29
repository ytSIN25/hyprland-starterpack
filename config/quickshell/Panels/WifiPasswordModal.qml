import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Components
import qs.Config
import qs.Services

// Diálogo de contraseña para conectar a una red WiFi nueva protegida.
// Redes WPA-Enterprise (802.1X, p. ej. universidad/eduroam): pide también el
// usuario y conecta vía nmcli (PEAP + MSCHAPv2, lo habitual en campus).
// Visible cuando Net.promptNetwork !== null. Centrado, captura teclado.
PanelWindow {
    id: modal

    property var modelData
    screen: modelData

    readonly property var net: Net.promptNetwork
    visible: net !== null

    property string pw: ""
    property string user: ""
    readonly property bool enterprise: Net.isEnterprise(net)
    property string err: ""
    property bool connecting: false

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-wifiprompt"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }

    // Cargado bajo demanda (LazyLoader en shell.qml): puede nacer ya visible
    // y entonces onVisibleChanged no se dispara, de ahí el onCompleted.
    Component.onCompleted: if (visible) _init()
    onVisibleChanged: if (visible) _init()
    function _init() {
        pw = ""; user = ""; err = ""; connecting = false
        // Si ya hay una conexión guardada, rellena el usuario con su identidad.
        if (enterprise && net) {
            identityProc.command = ["nmcli", "-g", "802-1x.identity", "connection", "show", "id", net.name]
            identityProc.running = true
        }
        focusTimer.restart()
    }
    Timer {
        id: focusTimer; interval: 60
        onTriggered: (modal.enterprise && modal.user === "") ? userField.forceFocus() : pwField.forceFocus()
    }

    readonly property bool canConnect: pw !== "" && (!enterprise || user.trim() !== "") && !connecting

    function tryConnect() {
        if (!canConnect || !modal.net) return
        modal.connecting = true
        modal.err = ""
        if (enterprise) {
            eapProc.command = ["sh", "-c", eapProc.script, "sh", modal.net.name, modal.user.trim()]
            eapProc.running = true
        } else {
            modal.net.connectWithPsk(pw)
        }
    }

    Process {
        id: identityProc
        stdout: StdioCollector {
            onStreamFinished: {
                const id = (this.text || "").trim()
                if (id !== "" && modal.user === "") { modal.user = id; pwField.forceFocus() }
            }
        }
    }

    // Crea o actualiza la conexión 802.1X y la activa. La contraseña entra por
    // stdin (no aparece en la línea de comandos de sh).
    Process {
        id: eapProc
        readonly property string script:
            'IFS= read -r pw; ssid="$1"; user="$2"; ' +
            'if nmcli connection show id "$ssid" >/dev/null 2>&1; then ' +
            '  nmcli connection modify id "$ssid" 802-1x.identity "$user" 802-1x.password "$pw" 802-1x.password-flags 0 || exit 2; ' +
            'else ' +
            '  nmcli connection add type wifi con-name "$ssid" ssid "$ssid" wifi-sec.key-mgmt wpa-eap ' +
            '    802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity "$user" 802-1x.password "$pw" >/dev/null || exit 2; ' +
            'fi; ' +
            'nmcli -w 40 connection up id "$ssid"'
        stdinEnabled: true
        stderr: StdioCollector { id: eapErr }
        onStarted: { write(modal.pw + "\n"); stdinEnabled = false }
        onExited: (code) => {
            stdinEnabled = true
            if (!modal.visible) return
            modal.connecting = false
            if (code === 0) { Net.clearPrompt(); return }
            const msg = (eapErr.text || "").trim().split("\n").pop()
            modal.err = I18n.tr("Could not connect. Check the username and password.")
                      + (msg !== "" ? "\n" + msg : "")
        }
    }

    // Reacciona al resultado de la conexión.
    Connections {
        target: Net.promptNetwork
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (Net.promptNetwork && Net.promptNetwork.connected) Net.clearPrompt()
        }
        function onConnectionFailed(reason) {
            if (modal.enterprise) return        // lo gestiona eapProc
            modal.connecting = false
            modal.err = I18n.tr("Could not connect. Check the password.")
        }
    }

    // Fondo oscuro: click cancela.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: modal.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        MouseArea { anchors.fill: parent; onClicked: Net.clearPrompt() }
    }

    // Tarjeta centrada.
    Rectangle {
        anchors.centerIn: parent
        width: Theme.panelWidth(screen, 360, 300, 0.86)
        height: content.implicitHeight + Theme.space18 * 2
        radius: Theme.barRadius + Theme.space2
        color: Theme.bgAlt
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.5)

        opacity: modal.visible ? 1 : 0
        scale: modal.visible ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // absorbe clicks

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space18 }
            spacing: Theme.space12

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10
                Text {
                    text: "󰤨"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.iconSize + 6
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: I18n.tr("Connect to WiFi network")
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modal.net?.name ?? ""
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        elide: Text.ElideRight
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: modal.enterprise
                text: I18n.tr("This network requires your account username and password.")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                wrapMode: Text.WordWrap
            }

            // Usuario (solo redes 802.1X).
            TextField {
                id: userField
                Layout.fillWidth: true
                visible: modal.enterprise
                leftIcon: "󰀄"
                placeholder: I18n.tr("Username")
                value: modal.user
                invalid: modal.err !== ""
                onEdited: (t) => { modal.user = t; modal.err = "" }
                onAccepted: pwField.forceFocus()
                onCanceled: Net.clearPrompt()
            }

            // Campo de contraseña.
            TextField {
                id: pwField
                Layout.fillWidth: true
                password: true
                leftIcon: "󰌾"
                placeholder: I18n.tr("Password")
                value: modal.pw
                invalid: modal.err !== ""
                onEdited: (t) => { modal.pw = t; modal.err = "" }
                onAccepted: modal.tryConnect()
                onCanceled: Net.clearPrompt()
            }

            // Error.
            Text {
                Layout.fillWidth: true
                visible: modal.err !== ""
                text: modal.err
                color: Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                wrapMode: Text.WordWrap
            }

            // Botones.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space2
                spacing: Theme.space8

                Item { Layout.fillWidth: true }

                TextButton {
                    text: I18n.tr("Cancel")
                    onClicked: Net.clearPrompt()
                }

                TextButton {
                    text: modal.connecting ? I18n.tr("Connecting...") : I18n.tr("Connect")
                    primary: true
                    enabled: modal.canConnect
                    onClicked: modal.tryConnect()
                }
            }
        }
    }
}
