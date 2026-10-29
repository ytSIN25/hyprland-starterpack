import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.Bar
import qs.Components
import qs.Config
import qs.Services

// Barra superior flotante: bordes redondeados y fondo translúcido.
PanelWindow {
    id: bar

    // Píldora de clima opcional (Ajustes → Clima → Mostrar en la barra):
    // icono según el estado del cielo + temperatura actual. Click abre el
    // Dashboard, donde vive la tarjeta completa. Componente en línea porque
    // comparte pantalla con el reloj y no se usa fuera de la barra.
    component WeatherWidget: Pill {
        visible: Settings.weatherShowInBar && Weather.enabled && Weather.ready
        interactive: true
        active: Globals.dashboardOpen
        onClicked: Globals.toggleDashboard()

        Text {
            text: Weather.icon
            color: Theme.yellow
            font.family: Theme.fontFamily
            font.pixelSize: Theme.barIconSize
        }
        Text {
            text: Weather.temp
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }

    // modelData lo inyecta Variants: es el QsScreen de este monitor.
    property var modelData
    screen: modelData

    // Borde de pantalla configurable (Ajustes → Shell → Disposición de la
    // barra): arriba, abajo, izquierda o derecha. El margen de separación
    // (barTopMargin) acompaña al borde activo; barMargin, a los extremos.
    readonly property string edge: Settings.barPosition
    readonly property bool atBottom: edge === "bottom"
    readonly property bool vertical: Theme.barVertical

    anchors {
        top: bar.edge !== "bottom"
        bottom: bar.edge !== "top"
        left: bar.edge !== "right"
        right: bar.edge !== "left"
    }

    margins {
        top: bar.edge === "top" ? Theme.barTopMargin : bar.vertical ? Theme.barMargin : 0
        bottom: bar.edge === "bottom" ? Theme.barTopMargin : bar.vertical ? Theme.barMargin : 0
        left: bar.edge === "left" ? Theme.barTopMargin : bar.vertical ? 0 : Theme.barMargin
        right: bar.edge === "right" ? Theme.barTopMargin : bar.vertical ? 0 : Theme.barMargin
    }

    implicitHeight: Theme.barThickness
    implicitWidth: Theme.barThickness
    color: "transparent"

    // Reserva el espacio justo de la barra + su margen.
    exclusiveZone: Theme.barThickness + Theme.barTopMargin

    // ── Extractor de paleta dinámica ─────────────────────────────────────────
    // Solo con el tema base "dynamic" y solo en la barra del monitor
    // principal: un Canvas fuera del viewport (su búfer pinta igual) reduce el
    // fondo de pantalla a 64×36 px, y Settings vota el tono dominante y deriva
    // la paleta completa. Se recalcula al cambiar de fondo.
    Loader {
        active: Settings.themeName === "dynamic" && bar.screen === Quickshell.screens[0]
        sourceComponent: Canvas {
            id: paletteCanvas
            x: -width; y: -height
            width: 64; height: 36
            renderTarget: Canvas.Image
            renderStrategy: Canvas.Immediate

            property string current: ""
            function analyze() {
                const p = Wallpaper.current
                if (p === "" || p === current)
                    return
                current = p
                loadImage("file://" + p)
                // Un fondo ya visto sigue en la caché del Canvas y no vuelve a
                // emitir imageLoaded: sin esto, volver a él no recalculaba la paleta.
                if (isImageLoaded("file://" + p))
                    requestPaint()
            }
            Component.onCompleted: analyze()
            Connections {
                target: Wallpaper
                function onCurrentChanged() { paletteCanvas.analyze() }
            }
            onImageLoaded: requestPaint()
            onPaint: {
                if (current === "")
                    return
                const url = "file://" + current
                if (!isImageLoaded(url))
                    return
                const ctx = getContext("2d")
                ctx.drawImage(url, 0, 0, width, height)
                Settings.computeDynamicPalette(ctx.getImageData(0, 0, width, height).data)
                unloadImage(url)
            }
        }
    }

    // Contenedor de la barra. En modo "separado" (Settings.barSeparated) no
    // pinta fondo propio: cada widget es su propia Pill independiente (ver
    // Components/Pill.qml) y flota suelta. En modo "combinado" sí pinta una
    // única tira de fondo continua detrás de todas las píldoras, como antes.
    Rectangle {
        id: barBg
        anchors.fill: parent
        radius: (!Settings.barSeparated && Settings.barFloating) ? Theme.barRadius : 0
        color: Settings.barSeparated ? "transparent" : Theme.barBg
        border.width: Settings.barSeparated ? 0 : Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.35)

        property bool entered: false
        Component.onCompleted: entered = true
        opacity: entered ? 1 : 0
        transform: Translate {
            // Entra deslizándose desde su borde (arriba, abajo, izquierda o
            // derecha, según dónde viva la barra).
            readonly property real hidden: barBg.entered ? 0 : Theme.barThickness + Theme.barTopMargin + Theme.dp(6)
            x: bar.edge === "left" ? -hidden : bar.edge === "right" ? hidden : 0
            y: bar.edge === "top" ? -hidden : bar.edge === "bottom" ? hidden : 0
            // OutQuint: recorre casi todo enseguida y dedica la cola a
            // asentarse — la barra "aterriza" en vez de frenar.
            Behavior on x { NumberAnimation { duration: 460; easing.type: Easing.OutQuint } }
            Behavior on y { NumberAnimation { duration: 460; easing.type: Easing.OutQuint } }
        }
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        // Un único eje: grupo inicial · hueco · (reloj en vertical) · hueco ·
        // grupo final. Los huecos elásticos empujan los grupos a los extremos
        // y centran el reloj; si no cabe todo, los grupos se juntan en vez de
        // solaparse.
        GridLayout {
            id: mainAxis
            anchors.fill: parent
            anchors.margins: bar.vertical ? Theme.space4 : Theme.gap
            anchors.topMargin: bar.vertical ? Theme.space6 : 0
            anchors.bottomMargin: bar.vertical ? Theme.space6 : 0
            flow: bar.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: 0
            rowSpacing: 0

            // Izquierda (arriba en vertical): workspaces + ventana activa
            ReorderRow {
                orderKey: "start"
                Layout.alignment: Qt.AlignCenter
                columnSpacing: Theme.gap
                rowSpacing: Theme.space4

                // Cada widget va en un HideSlot: así puede marcarse como oculto
                // (solo con SUPER+SHIFT+D) en Ajustes → Barra.
                HideSlot { objectName: "launcher"; cond: Settings.showLauncher; LauncherWidget {} }
                HideSlot { objectName: "workspaces"; cond: Settings.showWorkspaces; Workspaces { screen: bar.screen } }
                HideSlot { objectName: "sysmon"; cond: Settings.showSysmon; SysMonWidget {} }
                HideSlot {
                    objectName: "activeWindow"
                    cond: Settings.showActiveWindow && aw.active !== null && aw.appName !== ""
                    ActiveWindow { id: aw }
                }
            }

            Item { Layout.fillWidth: !bar.vertical; Layout.fillHeight: bar.vertical; Layout.minimumHeight: bar.vertical ? Theme.space4 : 0 }

            // Centro: en horizontal lo ocupa el notch (Bar/Notch.qml), una ventana
            // propia para poder desplegarse por debajo de la barra. En vertical el
            // notch se oculta y el reloj va aquí.
            ClockWidget {
                Layout.alignment: Qt.AlignCenter
                visible: bar.vertical
            }

            Item { Layout.fillWidth: !bar.vertical; Layout.fillHeight: bar.vertical; Layout.minimumHeight: bar.vertical ? Theme.space4 : 0 }

            // Derecha (abajo en vertical): bandeja + estado + batería.
            ReorderRow {
                orderKey: "end"
                Layout.alignment: Qt.AlignCenter
                columnSpacing: Theme.gap
                rowSpacing: Theme.space4

                HideSlot { objectName: "tray"; cond: Settings.showTray && SystemTray.items.values.length > 0; Tray {} }
                HideSlot { objectName: "weather"; cond: Settings.weatherShowInBar && Weather.enabled && Weather.ready; WeatherWidget {} }
                HideSlot { objectName: "connectivity"; cond: Settings.showConnectivity; ConnectivityAudioWidget {} }
                HideSlot { objectName: "vpn"; cond: Settings.showVpn; VpnWidget {} }
                HideSlot { objectName: "privacy"; cond: Settings.showPrivacy && Privacy.active; PrivacyWidget {} }
                HideSlot { objectName: "wazuh"; cond: Settings.showWazuh; WazuhWidget {} }
                HideSlot { objectName: "firewall"; cond: Settings.showFirewall; FirewallWidget {} }
                HideSlot { objectName: "gpuOffload"; cond: Settings.showGpuOffload; GpuOffloadWidget {} }
                HideSlot { objectName: "updates"; cond: Settings.showUpdates; UpdatesWidget {} }
                HideSlot { objectName: "diskClean"; cond: Settings.showDiskClean; DiskWidget {} }
                HideSlot { objectName: "logs"; cond: Settings.showLogs; LogsWidget {} }
                HideSlot { objectName: "aiUsage"; cond: Settings.showAiUsage; AiUsageWidget {} }
                HideSlot { objectName: "duolingo"; cond: Settings.showDuolingo; DuolingoWidget {} }
                HideSlot { objectName: "sshd"; cond: Settings.showSshd; SshdWidget {} }
                HideSlot { objectName: "pingIp"; cond: Settings.showPingIp; PingIpWidget {} }
                HideSlot { objectName: "wifiPass"; cond: Settings.showWifiPass; WifiPassWidget {} }
                HideSlot { objectName: "power"; cond: Power.available && Settings.showPowerProfile; PowerWidget {} }
                HideSlot { objectName: "caffeine"; cond: Settings.showCaffeine; CaffeineWidget {} }
                HideSlot { objectName: "battery"; cond: batt.present && Settings.showBattery; BatteryWidget { id: batt } }
                HideSlot { objectName: "clipboard"; cond: Settings.showClipboard; ClipboardWidget {} }
                HideSlot { objectName: "notifications"; cond: Settings.showNotifications; NotificationsWidget {} }
                HideSlot { objectName: "shutdown"; cond: Settings.showShutdown; ShutdownWidget {} }
            }
        }
    }
}
