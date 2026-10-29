import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.Components
import qs.Config
import qs.Panels
import qs.Services

// Píldora central negra estilo "dynamic island". Estados, de mayor a menor
// prioridad (el estado vive en Services/Island.qml):
//   picker   → selector de timer / stopwatch (clic derecho)
//   osd      → volumen o brillo con barra arrastrable
//   shot     → miniatura de la última captura (abrir / carpeta / arrastrar)
//   alert    → aviso transitorio (batería, Bluetooth, red, calendario…);
//              clic → su acción (enfocar terminal, abrir panel…)
//   expanded → al pasar el ratón: reproductor + hora/semana, o los
//              controles de la grabación / temporizador / sesiones de IA
//   rec      → grabando: punto rojo + tiempo
//   update   → pacman/yay en marcha: paquetes hechos / total
//   ai       → Claude / Codex trabajando: logo + tiempo (clic → su terminal)
//   timer    → timer o stopwatch compacto
//   music    → sonando: carátula + hora + barras animadas
//   clock    → solo la hora
// Rueda sobre el notch: volumen. Clic central: play/pausa.
// A la derecha del notch, puntos de privacidad (verde cámara, naranja micro).
// La ventana tiene siempre el tamaño máximo para no redimensionar la capa;
// la máscara limita la entrada al notch.
PanelWindow {
    id: root

    property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-notch"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors.top: true

    // Misma altura y posición vertical que las píldoras de la barra.
    readonly property int pillY: Theme.barTopMargin + (Theme.barHeight - Theme.barPillHeight) / 2
    readonly property int collapsedW: Theme.dp(110)
    readonly property int collapsedH: Theme.barPillHeight
    readonly property int expandedW: Theme.dp(420)
    readonly property int expandedH: Theme.dp(100)
    // La pestaña Alarm es más alta (lista / editor).
    readonly property int alarmListH: Theme.dp(244)
    readonly property int alarmEditH: Theme.dp(268)
    readonly property int pickerH: Island.pickerTab !== "alarm" ? Theme.dp(128)
                                 : Island.alarmEdit ? alarmEditH : alarmListH
    readonly property int timerW: Theme.dp(180)
    readonly property int musicW: Theme.dp(200)
    readonly property int recW: Theme.dp(150)
    readonly property int osdW: Theme.dp(300)
    readonly property int shotW: Theme.dp(360)
    readonly property int shotH: Theme.dp(84)
    readonly property int promptW: Island.prompt && Island.prompt.style === "call" ? Theme.dp(490) : Theme.dp(410)
    readonly property int promptH: Island.prompt && Island.prompt.style === "call" ? Theme.dp(70) : Theme.dp(92)
    // Hasta el ancho de las preguntas "call" (la ventana ya lo tiene)
    readonly property int alertW: Math.min(Theme.dp(490),
        Math.max(Theme.dp(260), alertRow.implicitWidth + Theme.dp(36)))

    implicitWidth: Math.max(expandedW, Theme.dp(490)) + Theme.dp(60)   // 490 = promptW estilo "call"
    implicitHeight: pillY + alarmEditH
    // Con la barra vertical el notch flotaría sobre las ventanas: se oculta
    // y el reloj pasa al centro de la barra (ver Bar.qml).
    visible: !Theme.barVertical
    mask: Region { item: notch }
    // Teclado solo mientras se edita una alarma (hora / etiqueta a mano), o
    // en exclusiva mientras la pregunta de SSH pide la contraseña (≤ 20 s).
    readonly property bool sshPwStage: !!Island.prompt && (Island.prompt.kind === "ssh" || Island.prompt.kind === "root")
                                       && !!Island.prompt.data && !!Island.prompt.data.pw
    WlrLayershell.keyboardFocus: sshPwStage ? WlrKeyboardFocus.Exclusive
        : Island.pickerOpen && Island.alarmEdit ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Reproductor: el que esté sonando, si no el primero (como MediaWidget).
    readonly property var players: Mpris.players?.values ?? []
    readonly property var player: {
        if (players.length === 0)
            return null
        for (let i = 0; i < players.length; i++)
            if (players[i].isPlaying)
                return players[i]
        return players[0]
    }
    readonly property bool hasMedia: player !== null
                                     && ((player.trackTitle || "") !== "" || (player.trackArtist || "") !== "")
    readonly property bool playing: hasMedia && (player?.isPlaying ?? false)
    readonly property bool recording: ScreenCapture.isRecording

    // Al salir se espera un poco antes de plegar: evita parpadeos al rozar
    // el borde o al moverse entre los botones.
    property bool expanded: false
    Timer {
        id: collapseDelay
        interval: 250
        onTriggered: root.expanded = false
    }
    // El selector se cierra al salir con el mismo retardo que el desplegado
    // del reproductor. Si se abrió por IPC y el ratón nunca entró, se le da
    // más margen para llegar hasta él.
    property bool pickerHovered: false
    Connections {
        target: Island
        function onPickerOpenChanged() { root.pickerHovered = Island.pickerOpen && hover.hovered }
    }
    Timer {
        interval: root.pickerHovered ? collapseDelay.interval : 5000
        running: Island.pickerOpen && !hover.hovered && !Island.alarmEdit
        onTriggered: Island.pickerOpen = false
    }
    // La miniatura no se va mientras el ratón esté encima.
    Timer {
        interval: 500
        repeat: true
        running: root.mode === "shot" && hover.hovered
        onTriggered: Island.holdShot()
    }
    // Una pregunta no caduca mientras el ratón esté encima.
    Timer {
        interval: 500
        repeat: true
        running: root.mode === "prompt" && hover.hovered
        onTriggered: Island.holdPrompt()
    }
    // El OSD no se esconde mientras el ratón esté encima (para arrastrar).
    Timer {
        interval: 500
        repeat: true
        running: root.mode === "osd" && hover.hovered
        onTriggered: Island.showOsd(Island.osdKind)
    }

    readonly property string mode: Island.pickerOpen ? "picker"
        : Island.osdKind !== "" ? "osd"
        : Island.shot ? "shot"
        : Island.prompt ? "prompt"
        : Island.alert ? "alert"
        : expanded ? "expanded"
        : recording ? "rec"
        : Island.upd ? "update"
        : DownloadWatch.busy ? "download"
        : Island.aiActive ? "ai"
        : Island.timerActive ? "timer"
        : playing ? "music"
        : "clock"

    readonly property var widths: ({
        picker: expandedW, expanded: expandedW, osd: osdW, alert: alertW,
        shot: shotW, prompt: promptW, rec: recW, update: timerW, download: timerW, ai: timerW, timer: timerW, music: musicW, clock: collapsedW
    })

    Rectangle {
        id: notch
        anchors.top: parent.top
        anchors.topMargin: root.pillY
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.widths[root.mode]
        height: root.mode === "picker" ? root.pickerH
              : root.mode === "expanded" ? root.expandedH
              : root.mode === "shot" ? root.shotH
              : root.mode === "prompt" ? root.promptH
              : root.collapsedH
        color: "black"
        radius: height > root.collapsedH ? Theme.dp(22) : height / 2
        clip: true

        Behavior on width { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on height { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }
        Behavior on radius { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }

        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered) {
                    if (Island.pickerOpen) root.pickerHovered = true
                    collapseDelay.stop()
                    root.expanded = true
                } else {
                    collapseDelay.restart()
                }
            }
        }

        // Clic derecho: selector de timer. Clic izquierdo sobre un aviso: lo
        // descarta. Va debajo del contenido para no tapar sus botones.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    Island.pickerOpen = !Island.pickerOpen
                else if (mouse.button === Qt.MiddleButton) {
                    if (root.player?.canTogglePlaying) root.player.togglePlaying()
                } else if (root.mode === "alert")
                    Island.alertClick()
                else if (root.mode === "ai") {
                    const s = Island.aiWaiting ?? Island.aiList[0]
                    if (s) Island.aiFocus(s.id)
                }
            }
        }
        // Rueda: volumen ±5 % por paso (acumula el delta para touchpads).
        WheelHandler {
            enabled: root.mode !== "picker"
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            property real acc: 0
            onWheel: (ev) => {
                acc += ev.angleDelta.y
                while (Math.abs(acc) >= 120) {
                    const dir = acc > 0 ? 1 : -1
                    acc -= dir * 120
                    Island.setVolume((Island.muted ? 0 : Island.volume) / 100 + dir * 0.05)
                }
            }
        }

        // ── Plegado: solo la hora ───────────────────────────────────────────
        Text {
            anchors.centerIn: parent
            text: Qt.formatDateTime(Time.now, Time.clockFormat)
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            opacity: root.mode === "clock" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
        }

        // ── Música: carátula · hora · barras ────────────────────────────────
        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(5)
            anchors.rightMargin: Theme.dp(14)
            opacity: root.mode === "music" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "music" ? 260 : 80 } }

            ClippingRectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: root.collapsedH - Theme.dp(10)
                height: width
                radius: Theme.dp(5)
                color: Theme.surface
                Image {
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Theme.dp(64)
                    sourceSize.height: Theme.dp(64)
                }
                Text {
                    anchors.centerIn: parent
                    visible: (root.player?.trackArtUrl ?? "") === ""
                    text: "󰝚"
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(11)
                }
            }
            Text {
                anchors.centerIn: parent
                text: Qt.formatDateTime(Time.now, Time.clockFormat)
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Theme.dp(14)
                spacing: Theme.dp(2)
                Repeater {
                    model: [430, 310, 520, 370]
                    Rectangle {
                        id: bar
                        required property int modelData
                        required property int index
                        width: Theme.dp(3)
                        height: Theme.dp(4)
                        radius: width / 2
                        anchors.bottom: parent.bottom
                        color: Theme.accent
                        SequentialAnimation on height {
                            running: root.mode === "music" && root.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: Theme.dp(14); duration: bar.modelData; easing.type: Easing.InOutSine }
                            NumberAnimation { to: Theme.dp(4 + bar.index * 2); duration: bar.modelData; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }

        // ── Actualización en marcha: paquete + hechos/total ─────────────────
        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(14)
            anchors.rightMargin: Theme.dp(14)
            opacity: root.mode === "update" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "update" ? 260 : 80 } }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Island.icons.pkg
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: !Island.upd ? ""
                    : Island.upd.phase === "download" ? I18n.tr("Downloading")
                    : Island.upd.phase === "build" ? I18n.tr("Building")
                    : Island.upd.phase === "wait" ? I18n.tr("Waiting")
                    : Island.upd.total > 0 ? Island.upd.done + "/" + Island.upd.total
                    : String(Island.upd.done)
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.features: { "tnum": 1 }
            }
            // Progreso como línea fina en la base de la píldora.
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.dp(4)
                anchors.left: parent.left
                height: Theme.dp(2)
                radius: 1
                width: parent.width * Island.updProgress
                visible: Island.upd !== null && Island.upd.total > 0
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: 250 } }
            }
        }

        // ── Descarga en curso: velocidad + línea animada (sin % conocido) ────
        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(14)
            anchors.rightMargin: Theme.dp(14)
            opacity: root.mode === "download" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "download" ? 260 : 80 } }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Island.icons.download
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: DownloadWatch.human(DownloadWatch.totalSpeed) + "/s"
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.features: { "tnum": 1 }
            }
            Item {
                id: dlTrack
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.dp(4)
                anchors.left: parent.left
                anchors.right: parent.right
                height: Theme.dp(2)
                clip: true
                Rectangle {
                    width: dlTrack.width * 0.3
                    height: parent.height
                    radius: 1
                    color: Theme.accent
                    NumberAnimation on x {
                        from: -dlTrack.width * 0.3; to: dlTrack.width
                        duration: 1400
                        loops: Animation.Infinite
                        running: root.mode === "download"
                    }
                }
            }
        }

        // ── Captura: miniatura + nombre + abrir / carpeta; se puede arrastrar ─
        RowLayout {
            id: shotRow
            readonly property var sh: Island.shot
            readonly property string fileUrl: sh ? "file://" + (sh.path || sh.preview) : ""
            anchors.fill: parent
            anchors.margins: Theme.dp(10)
            spacing: Theme.dp(12)
            opacity: root.mode === "shot" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "shot" ? 260 : 80 } }

            ClippingRectangle {
                id: thumb
                Layout.preferredWidth: Theme.dp(112)
                Layout.fillHeight: true
                radius: Theme.dp(10)
                color: Theme.surface
                Image {
                    anchors.fill: parent
                    // ?t= fuerza la recarga: la ruta de la miniatura es siempre la misma.
                    source: shotRow.sh ? "file://" + shotRow.sh.preview + "?t=" + shotRow.sh.t : ""
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Theme.dp(224)
                }
                // Arrastrar la miniatura a otra app suelta el archivo.
                Item {
                    id: dragProxy
                    anchors.fill: parent
                    Drag.active: shotDrag.active
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: ({ "text/uri-list": shotRow.fileUrl })
                }
                DragHandler {
                    id: shotDrag
                    target: null
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.dp(2)
                Text {
                    text: shotRow.sh && shotRow.sh.title ? shotRow.sh.title
                        : shotRow.sh && shotRow.sh.path ? I18n.tr("Screenshot saved") : I18n.tr("Screenshot copied")
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: shotRow.sh && shotRow.sh.subtitle ? shotRow.sh.subtitle
                        : shotRow.sh && shotRow.sh.path ? shotRow.sh.path.split("/").pop() : I18n.tr("In clipboard")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                    elide: Text.ElideMiddle
                }
                Row {
                    Layout.topMargin: Theme.dp(4)
                    spacing: Theme.dp(14)
                    visible: !!(shotRow.sh && shotRow.sh.path)
                    IslandButton {
                        text: Island.g(0xF0DCF) + " " + I18n.tr("Open")
                        font.pixelSize: Theme.fontSize - 2
                        onActivated: {
                            Quickshell.execDetached(["xdg-open", shotRow.sh.path])
                            Island.dismissShot()
                        }
                    }
                    IslandButton {
                        text: Island.g(0xF024B) + " " + I18n.tr("Folder")
                        font.pixelSize: Theme.fontSize - 2
                        onActivated: {
                            const p = shotRow.sh.path
                            Quickshell.execDetached(["xdg-open", p.slice(0, p.lastIndexOf("/")) || "/"])
                            Island.dismissShot()
                        }
                    }
                }
            }
            IslandButton {
                Layout.alignment: Qt.AlignTop
                text: "󰅖"
                font.pixelSize: Theme.iconSize
                onActivated: Island.dismissShot()
            }
        }

        // ── Pregunta: icono + texto + botones (USB nuevo, app nueva en red) ──
        Item {
            id: promptCard
            readonly property var p: Island.prompt
            anchors.fill: parent
            opacity: root.mode === "prompt" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "prompt" ? 260 : 80 } }
            // style "call": icono suelto · texto · botones a la derecha (SSH, escaneo)
            readonly property bool isCall: !!p && p.style === "call"

            RowLayout {
                visible: !promptCard.isCall
                anchors.fill: parent
                anchors.leftMargin: Theme.dp(12)
                anchors.rightMargin: Theme.dp(12)
                anchors.topMargin: Theme.dp(10)
                anchors.bottomMargin: Theme.dp(12)
                spacing: Theme.dp(12)

                Rectangle {
                    Layout.preferredWidth: Theme.dp(48)
                    Layout.preferredHeight: Theme.dp(48)
                    Layout.alignment: Qt.AlignVCenter
                    radius: Theme.dp(12)
                    color: promptCard.p ? Theme.withAlpha(promptCard.p.iconColor, 0.18) : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: promptCard.p ? promptCard.p.icon : ""
                        color: promptCard.p ? promptCard.p.iconColor : "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.dp(24)
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dp(2)
                    Text {
                        Layout.fillWidth: true
                        text: promptCard.p ? promptCard.p.title : ""
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: promptCard.p ? promptCard.p.value : ""
                        color: promptCard.p ? promptCard.p.valueColor : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideMiddle
                    }
                    Row {
                        Layout.topMargin: Theme.dp(5)
                        spacing: Theme.dp(6)
                        Repeater {
                            model: promptCard.p && promptCard.p.style !== "call" ? promptCard.p.buttons : []
                            delegate: Rectangle {
                                id: pbtn
                                required property var modelData
                                width: pbtnText.implicitWidth + Theme.dp(18)
                                height: Theme.dp(22)
                                radius: height / 2
                                color: Theme.withAlpha(pbtn.modelData.color || "white", pbtnMa.containsMouse ? 0.4 : 0.2)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text {
                                    id: pbtnText
                                    anchors.centerIn: parent
                                    text: pbtn.modelData.label
                                    color: pbtn.modelData.color || "white"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    font.bold: true
                                }
                                MouseArea {
                                    id: pbtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Island.promptAnswer(pbtn.modelData.id)
                                }
                            }
                        }
                    }
                }
                // Más preguntas en cola
                Text {
                    Layout.alignment: Qt.AlignTop
                    visible: Island.prompts.length > 1
                    text: "+" + (Island.prompts.length - 1)
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }
            // ── Estilo "llamada entrante": icono · quién · [secundario] [principal].
            // SSH tras Allow: candado · campo de contraseña · [Cancel] [Allow]
            RowLayout {
                visible: promptCard.isCall
                anchors.fill: parent
                anchors.leftMargin: Theme.dp(20)
                anchors.rightMargin: Theme.dp(14)
                anchors.topMargin: Theme.dp(6)
                anchors.bottomMargin: Theme.dp(10)
                spacing: Theme.dp(14)

                Text {
                    Layout.preferredWidth: Theme.dp(24)
                    Layout.alignment: Qt.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: promptCard.p ? promptCard.p.icon : ""
                    color: promptCard.p ? promptCard.p.iconColor : "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(22)
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.dp(4)
                    Text {
                        Layout.fillWidth: true
                        text: promptCard.p ? promptCard.p.title : ""
                        color: promptCard.p && promptCard.p.titleColor ? promptCard.p.titleColor : "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !root.sshPwStage
                        text: promptCard.p ? promptCard.p.value : ""
                        color: promptCard.p ? promptCard.p.valueColor : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        elide: Text.ElideMiddle
                    }
                    // Contraseña (Enter comprueba, Esc cancela)
                    Rectangle {
                        id: sshPwBox
                        visible: root.sshPwStage
                        readonly property bool wrong: root.sshPwStage && Island.prompt.data.tries > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.dp(24)
                        radius: Theme.dp(8)
                        color: Theme.withAlpha("white", 0.08)
                        border.width: 1
                        border.color: wrong ? Theme.withAlpha(Theme.red, 0.8)
                                    : sshPwField.activeFocus ? Theme.withAlpha("white", 0.25) : "transparent"
                        Behavior on border.color { ColorAnimation { duration: Theme.animFast } }
                        // Contraseña mal: sacudida corta, como en el login del Mac
                        transform: Translate { id: sshPwShake }
                        SequentialAnimation {
                            id: sshPwShakeAnim
                            NumberAnimation { target: sshPwShake; property: "x"; to: Theme.dp(-6); duration: 50 }
                            NumberAnimation { target: sshPwShake; property: "x"; to: Theme.dp(6); duration: 70 }
                            NumberAnimation { target: sshPwShake; property: "x"; to: Theme.dp(-4); duration: 60 }
                            NumberAnimation { target: sshPwShake; property: "x"; to: 0; duration: 50 }
                        }
                        TextInput {
                            id: sshPwField
                            anchors.fill: parent
                            anchors.leftMargin: Theme.dp(10)
                            anchors.rightMargin: Theme.dp(10)
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            passwordCharacter: "•"
                            readOnly: Island.sshPwBusy
                            color: "white"
                            selectionColor: Theme.withAlpha(Theme.green, 0.5)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            clip: true
                            Keys.onReturnPressed: Island.sshPassword(text)
                            Keys.onEnterPressed: Island.sshPassword(text)
                            Keys.onEscapePressed: Island.promptAnswer("decline")
                            // Escribir cuenta como estar encima: no caduca a mitad
                            onTextChanged: { Island.holdPrompt(); promptBar.restartCountdown() }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: sshPwField.text === ""
                                text: I18n.tr("Password")
                                color: Theme.fgMuted
                                font: sshPwField.font
                            }
                            Connections {
                                target: root
                                function onSshPwStageChanged() {
                                    sshPwField.text = ""
                                    if (root.sshPwStage) sshPwField.forceActiveFocus()
                                }
                            }
                            Connections {
                                target: Island
                                function onSshPwWrong() { sshPwField.text = ""; sshPwField.forceActiveFocus(); sshPwShakeAnim.restart(); promptBar.restartCountdown() }
                            }
                        }
                    }
                }
                // Botones: el "primary" lleno de su color, el resto gris. En la fase de
                // contraseña de SSH, Allow comprueba lo escrito.
                Repeater {
                    model: promptCard.isCall ? promptCard.p.buttons : []
                    delegate: Rectangle {
                        id: cbtn
                        required property var modelData
                        readonly property bool primary: !!modelData.primary
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: cbtnText.implicitWidth + Theme.dp(26)
                        Layout.preferredHeight: Theme.dp(30)
                        radius: height / 2
                        opacity: primary && Island.sshPwBusy ? 0.5 : 1
                        color: primary ? (cbtnMa.containsMouse ? Qt.lighter(modelData.color, 1.12) : modelData.color)
                                       : Theme.withAlpha("white", cbtnMa.containsMouse ? 0.2 : 0.12)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            id: cbtnText
                            anchors.centerIn: parent
                            text: cbtn.modelData.label
                            color: cbtn.primary ? (cbtn.modelData.ink || "black") : "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                        MouseArea {
                            id: cbtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.sshPwStage && cbtn.modelData.id === "allow" ? Island.sshPassword(sshPwField.text)
                                                                                       : Island.promptAnswer(cbtn.modelData.id)
                        }
                    }
                }
            }

            // Cuenta atrás: línea fina abajo que se vacía (se para con el ratón encima).
            Rectangle {
                id: promptBar
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.dp(5)
                anchors.horizontalCenter: parent.horizontalCenter
                height: Theme.dp(2)
                radius: 1
                color: !promptCard.p ? "transparent"
                     : promptCard.isCall ? Theme.withAlpha("white", 0.25) : Theme.withAlpha(promptCard.p.iconColor, 0.7)
                readonly property real full: parent.width - Theme.dp(48)
                width: full
                NumberAnimation on width {
                    id: promptAnim
                    running: false
                }
                Connections {
                    target: Island
                    function on_PromptKeyChanged() { promptBar.restartCountdown() }
                }
                Timer {
                    // holdPrompt() reinicia el plazo: la línea se rellena mientras hay ratón.
                    interval: 500
                    repeat: true
                    running: root.mode === "prompt" && hover.hovered
                    onTriggered: { promptAnim.stop(); promptBar.width = promptBar.full }
                }
                Connections {
                    target: hover
                    function onHoveredChanged() { if (!hover.hovered && root.mode === "prompt") promptBar.restartCountdown() }
                }
                function restartCountdown() {
                    promptAnim.stop()
                    if (!Island.prompt) return
                    width = full
                    promptAnim.from = full
                    promptAnim.to = 0
                    promptAnim.duration = Island.prompt.ms
                    promptAnim.start()
                }
            }
        }

        // ── IA trabajando: logo(s) girando + tiempo de la sesión más antigua ─
        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(14)
            anchors.rightMargin: Theme.dp(14)
            opacity: root.mode === "ai" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "ai" ? 260 : 80 } }

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.dp(6)
                ClaudeMark {
                    visible: Island.aiClaude
                    size: Theme.dp(15)
                    color: Island.claudeColor
                    RotationAnimation on rotation {
                        running: root.mode === "ai" && root.visible && Island.aiClaude
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 6000
                    }
                }
                CodexMark {
                    visible: Island.aiCodex
                    size: Theme.dp(15)
                    color: Island.codexColor
                    RotationAnimation on rotation {
                        running: root.mode === "ai" && root.visible && Island.aiCodex
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 6000
                    }
                }
            }
            // Esperando permiso: "Needs you" en amarillo latiendo; si no, tiempo.
            Text {
                id: aiTime
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                readonly property var first: Island.aiList.length > 0 ? Island.aiList[0] : null
                readonly property bool waiting: Island.aiWaiting !== null
                text: waiting ? I18n.tr("Needs you")
                    : first ? Island.formatDuration(Island.aiElapsed(first)) : ""
                color: waiting ? Theme.yellow : first ? Island.aiColor(first.agent) : "white"
                font.family: Theme.fontFamily
                font.pixelSize: waiting ? Theme.fontSize : Theme.fontSize + 1
                font.bold: true
                font.features: { "tnum": 1 }
                SequentialAnimation on opacity {
                    running: root.mode === "ai" && aiTime.waiting
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) aiTime.opacity = 1
                    NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                }
            }
        }

        // ── Timer / stopwatch compacto ──────────────────────────────────────
        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(14)
            anchors.rightMargin: Theme.dp(14)
            opacity: root.mode === "timer" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "timer" ? 260 : 80 } }

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Island.paused ? "󰏤" : Island.timerIcon
                color: Island.timerColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Island.timerText
                color: Island.timerColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        // ── Grabando: punto rojo + tiempo ───────────────────────────────────
        Item {
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(16)
            anchors.rightMargin: Theme.dp(14)
            opacity: root.mode === "rec" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "rec" ? 260 : 80 } }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.dp(10); height: width
                radius: width / 2
                color: ScreenCapture.isPaused ? Theme.yellow : Theme.red
                SequentialAnimation on opacity {
                    running: root.mode === "rec" && !ScreenCapture.isPaused && root.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 720; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 720; easing.type: Easing.InOutSine }
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: ScreenCapture.formatElapsed(ScreenCapture.recordingElapsed)
                color: ScreenCapture.isPaused ? Theme.yellow : Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        // ── OSD: icono · barra arrastrable · porcentaje ─────────────────────
        RowLayout {
            id: osdRow
            readonly property bool isVol: Island.osdKind === "volume"
            readonly property int value: isVol ? (Island.muted ? 0 : Island.volume) : Brightness.percent
            readonly property color tint: isVol && Island.muted ? Theme.fgMuted : "white"
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(16)
            anchors.rightMargin: Theme.dp(16)
            spacing: Theme.dp(12)
            opacity: root.mode === "osd" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "osd" ? 260 : 80 } }

            Text {
                Layout.preferredWidth: Theme.dp(18)
                horizontalAlignment: Text.AlignHCenter
                text: !osdRow.isVol ? Island.icons.brightness
                    : Island.muted ? "󰝟"
                    : Island.volume === 0 ? "󰖁"
                    : Island.volume < 34 ? "󰕿"
                    : Island.volume < 67 ? "󰖀"
                    : "󰕾"
                color: osdRow.tint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: osdDrag.pressed ? Theme.dp(8) : Theme.dp(6)
                    radius: height / 2
                    color: Theme.withAlpha("white", 0.2)
                    Behavior on height { NumberAnimation { duration: Theme.animFast } }
                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * Math.min(1, osdRow.value / 100)
                        color: osdRow.tint
                        Behavior on width { NumberAnimation { duration: osdDrag.pressed ? 0 : 120; easing.type: Easing.OutCubic } }
                    }
                }
                MouseArea {
                    id: osdDrag
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    function apply(x) {
                        const f = Math.max(0, Math.min(1, x / width))
                        if (osdRow.isVol) Island.setVolume(f)
                        else Brightness.setPercent(f * 100)
                        Island.showOsd(Island.osdKind)
                    }
                    onPressed: (mouse) => apply(mouse.x)
                    onPositionChanged: (mouse) => { if (pressed) apply(mouse.x) }
                }
            }
            Text {
                Layout.preferredWidth: Theme.dp(34)
                horizontalAlignment: Text.AlignRight
                text: osdRow.isVol && Island.muted ? "" : osdRow.value + "%"
                color: osdRow.tint
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.features: { "tnum": 1 }
            }
        }

        // ── Aviso: título a la izquierda, valor (+batería) a la derecha ─────
        RowLayout {
            id: alertRow
            readonly property var a: Island.alert
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(16)
            anchors.rightMargin: Theme.dp(14)
            spacing: Theme.dp(8)
            opacity: root.mode === "alert" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: root.mode === "alert" ? 260 : 80 } }

            ClippingRectangle {
                visible: (alertRow.a?.art ?? "") !== ""
                Layout.preferredWidth: root.collapsedH - Theme.dp(8)
                Layout.preferredHeight: root.collapsedH - Theme.dp(8)
                radius: Theme.dp(5)
                color: Theme.surface
                Image {
                    anchors.fill: parent
                    source: alertRow.a?.art ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Theme.dp(64)
                    sourceSize.height: Theme.dp(64)
                }
            }
            ClaudeMark {
                visible: (alertRow.a?.logo ?? "") === "claude"
                size: Theme.dp(15)
                color: Island.claudeColor
            }
            CodexMark {
                visible: (alertRow.a?.logo ?? "") === "codex"
                size: Theme.dp(15)
                color: Island.codexColor
            }
            Text {
                visible: (alertRow.a?.icon ?? "") !== "" && (alertRow.a?.art ?? "") === ""
                text: alertRow.a?.icon ?? ""
                color: alertRow.a?.iconColor ?? "white"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.iconSize
            }
            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: Theme.dp(220)
                text: alertRow.a?.title ?? ""
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.maximumWidth: Theme.dp(240)
                text: alertRow.a?.value ?? ""
                color: alertRow.a?.valueColor ?? "white"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: (alertRow.a?.battery ?? -1) >= 0
                elide: Text.ElideRight
            }
            IslandBattery {
                visible: (alertRow.a?.battery ?? -1) >= 0
                pct: alertRow.a?.battery ?? 0
                charging: alertRow.a?.charging ?? false
                tint: alertRow.a?.valueColor ?? "white"
            }
        }

        // ── Desplegado: reproductor + (hora y semana | grabación | timer) ───
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.dp(14)
            spacing: Theme.dp(12)
            opacity: root.mode === "expanded" ? 1 : 0
            visible: opacity > 0
            // Aparece cuando el notch ya casi ha crecido, desaparece al momento.
            Behavior on opacity {
                NumberAnimation { duration: root.mode === "expanded" ? 260 : 80; easing.type: Easing.OutCubic }
            }

            ClippingRectangle {
                Layout.preferredWidth: Theme.dp(64)
                Layout.preferredHeight: Theme.dp(64)
                radius: Theme.dp(10)
                color: Theme.surface

                Image {
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: Theme.dp(128)
                    sourceSize.height: Theme.dp(128)
                }
                Text {
                    anchors.centerIn: parent
                    visible: (root.player?.trackArtUrl ?? "") === ""
                    text: "󰝚"
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(24)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.dp(2)

                Text {
                    Layout.fillWidth: true
                    text: root.hasMedia ? (root.player.trackTitle || "") : I18n.tr("Nothing playing")
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.hasMedia
                    text: root.player?.trackArtist ?? ""
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
                // Sin música: próximo evento del calendario (si lo hay).
                Text {
                    Layout.fillWidth: true
                    visible: !root.hasMedia && Island.nextEvent !== null
                    text: Island.nextEvent
                          ? Island.icons.calendar + "  " + Qt.formatTime(new Date(Island.nextEvent.start),
                                Settings.clock24h ? "HH:mm" : "h:mm AP") + "  " + Island.nextEvent.title
                          : ""
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
                Row {
                    visible: root.hasMedia
                    spacing: Theme.dp(10)
                    Layout.topMargin: Theme.dp(4)

                    IslandButton {
                        text: "󰒮"
                        enabled_: root.player?.canGoPrevious ?? false
                        onActivated: root.player.previous()
                    }
                    IslandButton {
                        text: (root.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
                        enabled_: root.player?.canTogglePlaying ?? false
                        onActivated: root.player.togglePlaying()
                    }
                    IslandButton {
                        text: "󰒭"
                        enabled_: root.player?.canGoNext ?? false
                        onActivated: root.player.next()
                    }
                }
            }

            // Hora grande + tira de la semana (hoy ±3).
            ColumnLayout {
                visible: !root.recording && !Island.upd && !DownloadWatch.busy && !Island.timerActive && !Island.aiActive
                spacing: Theme.dp(4)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(Time.now, Time.clockFormat)
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(20)
                    font.bold: true
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.dp(4)

                    Repeater {
                        model: 7
                        Column {
                            required property int index
                            readonly property date day: {
                                const d = new Date(Time.today)
                                d.setDate(d.getDate() + index - 3)
                                return d
                            }
                            readonly property bool isToday: index === 3
                            spacing: Theme.dp(1)
                            opacity: isToday ? 1 : 0.5

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDate(parent.day, "ddd").charAt(0)
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.dp(9)
                            }
                            Rectangle {
                                width: Theme.dp(20); height: Theme.dp(20)
                                radius: width / 2
                                color: parent.isToday ? Theme.accent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.parent.day.getDate()
                                    color: parent.parent.isToday ? Theme.bg : "white"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.dp(10)
                                    font.bold: parent.parent.isToday
                                }
                            }
                        }
                    }
                }
            }

            // Grabación: tiempo + pausa / captura / detener.
            ColumnLayout {
                visible: root.recording
                spacing: Theme.dp(6)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: ScreenCapture.formatElapsed(ScreenCapture.recordingElapsed)
                    color: ScreenCapture.isPaused ? Theme.yellow : Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(22)
                    font.bold: true
                    font.features: { "tnum": 1 }
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.dp(14)
                    IslandButton {
                        text: ScreenCapture.isPaused ? "󰐊" : "󰏤"
                        onActivated: ScreenCapture.isPaused ? ScreenCapture.resumeRecording()
                                                            : ScreenCapture.pauseRecording()
                    }
                    IslandButton {
                        text: "󰄀"
                        onActivated: ScreenCapture.captureWhileRecording()
                    }
                    IslandButton {
                        text: "󰓛"
                        onActivated: ScreenCapture.stopRecording()
                    }
                }
            }

            // Actualización: paquete actual + barra + hechos/total.
            ColumnLayout {
                visible: !root.recording && Island.upd !== null
                Layout.preferredWidth: Theme.dp(150)
                spacing: Theme.dp(4)
                Text {
                    text: Island.icons.pkg + "  " + (!Island.upd ? ""
                          : Island.upd.phase === "download" ? I18n.tr("Downloading")
                          : Island.upd.phase === "build" ? I18n.tr("Building AUR")
                          : Island.upd.phase === "wait" ? I18n.tr("Waiting for you")
                          : I18n.tr("Updating"))
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: Island.upd ? (Island.upd.pkg || "…") : ""
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.dp(3)
                    radius: height / 2
                    color: Theme.withAlpha(Theme.accent, 0.25)
                    Rectangle {
                        width: parent.width * Island.updProgress
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 250 } }
                    }
                }
                Text {
                    text: !Island.upd ? "" : Island.upd.total > 0
                          ? I18n.tr("%1 of %2").arg(Island.upd.done).arg(Island.upd.total)
                          : I18n.tr("%1 packages").arg(Island.upd.done)
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }

            // Descargas: nombre + tamaño + velocidad.
            ColumnLayout {
                visible: !root.recording && !Island.upd && DownloadWatch.busy
                Layout.preferredWidth: Theme.dp(150)
                spacing: Theme.dp(4)
                Text {
                    text: Island.icons.download + "  " + I18n.tr("Downloading")
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
                Repeater {
                    model: DownloadWatch.active.slice(0, 3)
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            elide: Text.ElideMiddle
                        }
                        Text {
                            text: DownloadWatch.human(modelData.bytes) + " · " + DownloadWatch.human(modelData.speed) + "/s"
                            color: Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }

            // IA: una fila por sesión (logo · carpeta · tiempo). Clic → su terminal.
            ColumnLayout {
                visible: !root.recording && !Island.upd && !DownloadWatch.busy && Island.aiActive
                Layout.preferredWidth: Theme.dp(150)
                spacing: Theme.dp(6)

                Repeater {
                    model: Island.aiList.slice(0, 3)
                    RowLayout {
                        id: aiRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.dp(6)
                        TapHandler {
                            enabled: /^0x/.test(aiRow.modelData.win || "")
                            cursorShape: Qt.PointingHandCursor
                            onTapped: Island.aiFocus(aiRow.modelData.id)
                        }
                        Item {
                            Layout.preferredWidth: Theme.dp(14)
                            Layout.preferredHeight: Theme.dp(14)
                            ClaudeMark {
                                anchors.centerIn: parent
                                visible: aiRow.modelData.agent === "claude"
                                size: Theme.dp(14)
                                color: Island.claudeColor
                            }
                            CodexMark {
                                anchors.centerIn: parent
                                visible: aiRow.modelData.agent === "codex"
                                size: Theme.dp(14)
                                color: Island.codexColor
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: aiRow.modelData.cwd ? aiRow.modelData.cwd.split("/").pop() || "/"
                                                      : Island.aiName(aiRow.modelData.agent)
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            elide: Text.ElideRight
                        }
                        Text {
                            text: aiRow.modelData.attention > 0 ? I18n.tr("waiting")
                                : Island.formatDuration(Island.aiElapsed(aiRow.modelData))
                            color: aiRow.modelData.attention > 0 ? Theme.yellow : Island.aiColor(aiRow.modelData.agent)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.bold: true
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }

            // Temporizador en marcha: etiqueta, tiempo, progreso y controles.
            ColumnLayout {
                visible: !root.recording && !Island.upd && !DownloadWatch.busy && !Island.aiActive && Island.timerActive
                spacing: Theme.dp(3)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Island.timerLabel
                    color: Island.timerColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(10)
                    font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Island.timerText
                    color: Island.timerColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(20)
                    font.bold: true
                    font.features: { "tnum": 1 }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.dp(3)
                    radius: height / 2
                    color: Theme.withAlpha(Island.timerColor, 0.25)
                    Rectangle {
                        width: parent.width * Island.timerProgress
                        height: parent.height
                        radius: parent.radius
                        color: Island.timerColor
                        Behavior on width { NumberAnimation { duration: 250 } }
                    }
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.dp(14)
                    IslandButton {
                        text: Island.paused ? "󰐊" : "󰏤"
                        onActivated: Island.togglePause()
                    }
                    // +1 min (timer) o reiniciar (stopwatch).
                    IslandButton {
                        text: Island.kind === "timer" ? "+1" : "󰑐"
                        font.pixelSize: Island.kind === "timer" ? Theme.fontSize : Theme.barIconSize
                        font.bold: Island.kind === "timer"
                        onActivated: Island.kind === "timer" ? Island.addTime(60) : Island.startStopwatch()
                    }
                    IslandButton {
                        text: "󰅖"
                        onActivated: Island.cancelTimer()
                    }
                }
            }
        }

        // ── Selector: pestañas timer / stopwatch ────────────────────────────
        ColumnLayout {
            id: picker
            readonly property color tabColor: Island.pickerTab === "stopwatch" ? Theme.cyan
                                            : Island.pickerTab === "alarm" ? Theme.magenta : Theme.orange
            anchors.fill: parent
            anchors.margins: Theme.dp(14)
            spacing: Theme.dp(8)
            opacity: root.mode === "picker" ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                NumberAnimation { duration: root.mode === "picker" ? 260 : 80; easing.type: Easing.OutCubic }
            }

            Row {
                spacing: Theme.dp(6)
                Repeater {
                    model: [
                        { "id": "timer", "label": I18n.tr("Timer"), "icon": Island.icons.timer },
                        { "id": "stopwatch", "label": I18n.tr("Stopwatch"), "icon": Island.icons.stopwatch },
                        { "id": "alarm", "label": I18n.tr("Alarm"), "icon": Island.icons.alarm }
                    ]
                    Rectangle {
                        id: tab
                        required property var modelData
                        readonly property bool sel: Island.pickerTab === modelData.id
                        width: tabText.implicitWidth + Theme.dp(18)
                        height: Theme.dp(22)
                        radius: height / 2
                        color: sel ? Theme.withAlpha("white", 0.16)
                             : tabMa.containsMouse ? Theme.withAlpha("white", 0.08) : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            id: tabText
                            anchors.centerIn: parent
                            text: tab.modelData.icon + "  " + tab.modelData.label
                            color: tab.sel ? "white" : Theme.fgMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: tab.sel
                        }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Island.pickerTab = tab.modelData.id; Island.alarmEdit = null }
                        }
                    }
                }
            }

            RowLayout {
                visible: Island.pickerTab !== "alarm"
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.dp(14)

                // Valor grande: rueda para ajustar (timer: ±1 min, Mayús ±5).
                Text {
                    Layout.preferredWidth: Theme.dp(96)
                    text: Island.pickerTab === "stopwatch" ? "00:00"
                        : Island.formatDuration(Island.pickerMinutes * 60)
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(26)
                    font.bold: true
                    font.features: { "tnum": 1 }

                    WheelHandler {
                        enabled: Island.pickerTab === "timer"
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (ev) => {
                            const step = (ev.modifiers & Qt.ShiftModifier) ? 5 : 1
                            const dir = ev.angleDelta.y > 0 ? 1 : -1
                            Island.pickerMinutes = Math.max(1, Math.min(180, Island.pickerMinutes + dir * step))
                        }
                    }
                }

                // Timer: presets en minutos.
                GridLayout {
                    visible: Island.pickerTab === "timer"
                    Layout.fillWidth: true
                    columns: 4
                    rowSpacing: Theme.dp(6)
                    columnSpacing: Theme.dp(6)

                    Repeater {
                        model: [1, 3, 5, 10, 15, 25, 45, 60]
                        Rectangle {
                            id: chip
                            required property int modelData
                            readonly property bool sel: Island.pickerMinutes === modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.dp(24)
                            radius: height / 2
                            color: sel ? Theme.orange
                                 : chipMa.containsMouse ? Theme.withAlpha(Theme.orange, 0.3)
                                 : Theme.withAlpha("white", 0.1)
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Text {
                                anchors.centerIn: parent
                                text: chip.modelData + "m"
                                color: chip.sel ? "black" : "white"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                            }
                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Island.pickerMinutes = chip.modelData
                                onDoubleClicked: Island.startTimer(chip.modelData * 60)
                            }
                        }
                    }
                }

                // Stopwatch: solo una línea de ayuda.
                Text {
                    visible: Island.pickerTab === "stopwatch"
                    Layout.fillWidth: true
                    text: I18n.tr("Counts up until you stop it")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.preferredWidth: Theme.dp(46)
                    Layout.preferredHeight: Theme.dp(46)
                    radius: width / 2
                    color: startMa.containsMouse ? Qt.lighter(picker.tabColor, 1.15) : picker.tabColor
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: Theme.dp(2)
                        text: "󰐊"
                        color: "black"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.dp(22)
                    }
                    MouseArea {
                        id: startMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (Island.pickerTab === "stopwatch") Island.startStopwatch()
                            else Island.startTimer(Island.pickerMinutes * 60)
                        }
                    }
                }
            }
            // ── Alarmas: lista (interruptor on/off; clic = editar) ──────────
            ColumnLayout {
                visible: Island.pickerTab === "alarm" && !Island.alarmEdit
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.dp(6)

                ListView {
                    id: alarmList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Theme.dp(6)
                    boundsBehavior: Flickable.StopAtBounds
                    model: Alarms.alarms
                    delegate: Rectangle {
                        id: arow
                        required property var modelData
                        width: alarmList.width
                        height: Theme.dp(46)
                        radius: Theme.dp(12)
                        color: arowMa.containsMouse ? Theme.withAlpha("white", 0.1) : Theme.withAlpha("white", 0.05)
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        MouseArea {
                            id: arowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Island.editAlarm(arow.modelData)
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.dp(12)
                            anchors.rightMargin: Theme.dp(10)
                            spacing: Theme.dp(10)
                            Text {
                                text: Alarms.timeText(arow.modelData.h, arow.modelData.m, Settings.clock24h)
                                color: arow.modelData.on ? "white" : Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.dp(22)
                                font.bold: true
                                font.features: { "tnum": 1 }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: I18n.tr(Alarms.daysText(arow.modelData.days))
                                      + (arow.modelData.label ? " · " + arow.modelData.label : "")
                                color: Theme.fgMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                elide: Text.ElideRight
                            }
                            Switch {
                                checked: arow.modelData.on
                                onColor: Theme.magenta
                                offColor: Theme.withAlpha("white", 0.12)
                                offBorderColor: "transparent"
                                onToggled: Alarms.toggle(arow.modelData.id)
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: alarmList.count === 0
                        text: I18n.tr("No alarms yet")
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dp(8)
                    Text {
                        Layout.fillWidth: true
                        text: Alarms.next
                            ? Island.icons.alarm + "  " + Qt.formatDateTime(Alarms.next.at, "ddd ")
                              + Alarms.timeText(Alarms.next.alarm.h, Alarms.next.alarm.m, Settings.clock24h)
                              + " · " + Alarms.untilText(Alarms.next.at)
                            : (alarmList.count > 0 ? I18n.tr("All alarms off") : "")
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.preferredWidth: Theme.dp(30)
                        Layout.preferredHeight: Theme.dp(30)
                        radius: width / 2
                        color: addMa.containsMouse ? Qt.lighter(Theme.magenta, 1.15) : Theme.magenta
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f0415}"
                            color: "black"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.dp(18)
                        }
                        MouseArea {
                            id: addMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Island.editAlarm(null)
                        }
                    }
                }
            }

            // ── Alarmas: editor (hora, días, etiqueta) ──────────────────────
            ColumnLayout {
                id: alarmEditor
                readonly property var e: Island.alarmEdit
                readonly property bool open: Island.pickerTab === "alarm" && e !== null
                visible: open
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.dp(8)
                // Al abrir el editor se carga la etiqueta (luego es del campo).
                onOpenChanged: if (open) labelField.text = e.label

                function save() {
                    Island.setAlarmEdit({ label: labelField.text.trim() })
                    Island.saveAlarm()
                }

                // Hora: rueda / flechas / escribir. En 12 h, AM/PM al lado.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.dp(4)
                    AlarmSpin { field: "h" }
                    Text {
                        text: ":"
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.dp(34)
                        font.bold: true
                    }
                    AlarmSpin { field: "m" }
                    Column {
                        visible: !Settings.clock24h
                        Layout.leftMargin: Theme.dp(8)
                        spacing: Theme.dp(4)
                        Repeater {
                            model: ["AM", "PM"]
                            Rectangle {
                                id: ampm
                                required property string modelData
                                readonly property bool sel: alarmEditor.e && ((alarmEditor.e.h >= 12) === (modelData === "PM"))
                                width: Theme.dp(40); height: Theme.dp(24)
                                radius: height / 2
                                color: sel ? Theme.magenta : ampmMa.containsMouse ? Theme.withAlpha("white", 0.14) : Theme.withAlpha("white", 0.07)
                                Text {
                                    anchors.centerIn: parent
                                    text: ampm.modelData
                                    color: ampm.sel ? "black" : "white"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                }
                                MouseArea {
                                    id: ampmMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!ampm.sel) Island.setAlarmEdit({ h: (alarmEditor.e.h + 12) % 24 })
                                }
                            }
                        }
                    }
                }

                // Días (vacío = una vez)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dp(6)
                    Repeater {
                        model: 7
                        Rectangle {
                            id: dayChip
                            required property int index
                            readonly property bool sel: alarmEditor.e !== null && alarmEditor.e.days.indexOf(index) !== -1
                            Layout.preferredWidth: Theme.dp(28)
                            Layout.preferredHeight: Theme.dp(28)
                            radius: width / 2
                            color: sel ? Theme.magenta : dayMa.containsMouse ? Theme.withAlpha("white", 0.14) : Theme.withAlpha("white", 0.07)
                            Behavior on color { ColorAnimation { duration: Theme.animFast } }
                            Text {
                                anchors.centerIn: parent
                                text: Alarms.dayLetters[dayChip.index]
                                color: dayChip.sel ? "black" : "white"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                            }
                            MouseArea {
                                id: dayMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const d = alarmEditor.e.days
                                    Island.setAlarmEdit({ days: dayChip.sel ? d.filter(x => x !== dayChip.index)
                                                                            : d.concat([dayChip.index]) })
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: alarmEditor.e ? I18n.tr(Alarms.daysText(alarmEditor.e.days)) : ""
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        elide: Text.ElideRight
                    }
                }

                // Etiqueta
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.dp(30)
                    radius: Theme.dp(10)
                    color: Theme.withAlpha("white", 0.07)
                    border.width: labelField.activeFocus ? 1 : 0
                    border.color: Theme.magenta
                    TextInput {
                        id: labelField
                        anchors.fill: parent
                        anchors.leftMargin: Theme.dp(10)
                        anchors.rightMargin: Theme.dp(10)
                        verticalAlignment: TextInput.AlignVCenter
                        color: "white"
                        selectionColor: Theme.withAlpha(Theme.magenta, 0.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        maximumLength: 40
                        clip: true
                        Keys.onReturnPressed: alarmEditor.save()
                        Keys.onEnterPressed: alarmEditor.save()
                        Keys.onEscapePressed: Island.alarmEdit = null
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: labelField.text === "" && !labelField.activeFocus
                            text: I18n.tr("Label (optional)")
                            color: Theme.fgMuted
                            font: labelField.font
                        }
                    }
                }

                // Borrar · Cancelar · Guardar
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dp(8)
                    Repeater {
                        model: [
                            { id: "delete", label: "\u{f0a7a}  " + I18n.tr("Delete"), color: Theme.red,
                              show: alarmEditor.e !== null && alarmEditor.e.id !== "" },
                            { id: "spacer" },
                            { id: "cancel", label: I18n.tr("Cancel"), color: Theme.fgMuted, show: true },
                            { id: "save", label: I18n.tr("Save"), color: Theme.magenta, show: true, filled: true }
                        ]
                        Item {
                            id: abtn
                            required property var modelData
                            Layout.fillWidth: modelData.id === "spacer"
                            Layout.preferredWidth: modelData.id === "spacer" ? 0 : abtnText.implicitWidth + Theme.dp(26)
                            Layout.preferredHeight: Theme.dp(28)
                            visible: modelData.id === "spacer" || modelData.show
                            Rectangle {
                                anchors.fill: parent
                                visible: abtn.modelData.id !== "spacer"
                                radius: height / 2
                                color: abtn.modelData.filled ? (abtnMa.containsMouse ? Qt.lighter(abtn.modelData.color, 1.15) : abtn.modelData.color)
                                     : abtnMa.containsMouse ? Theme.withAlpha(abtn.modelData.color || "white", 0.22)
                                     : Theme.withAlpha(abtn.modelData.color || "white", 0.12)
                                Behavior on color { ColorAnimation { duration: Theme.animFast } }
                                Text {
                                    id: abtnText
                                    anchors.centerIn: parent
                                    text: abtn.modelData.label || ""
                                    color: abtn.modelData.filled ? "black" : (abtn.modelData.color || "white")
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: true
                                }
                                MouseArea {
                                    id: abtnMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (abtn.modelData.id === "save") alarmEditor.save()
                                        else if (abtn.modelData.id === "delete") Island.deleteAlarm()
                                        else Island.alarmEdit = null
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Privacidad: cámara (verde) y micro (naranja), como en iOS ───────────
    Row {
        anchors.left: notch.right
        anchors.leftMargin: Theme.dp(6)
        y: root.pillY + (root.collapsedH - height) / 2
        spacing: Theme.dp(4)
        visible: notch.height <= root.collapsedH && notch.width < root.expandedW
        Rectangle {
            visible: Privacy.cameraInUse
            width: Theme.dp(7); height: width; radius: width / 2
            color: Theme.green
        }
        Rectangle {
            visible: Privacy.micInUse
            width: Theme.dp(7); height: width; radius: width / 2
            color: Theme.orange
        }
    }
}
