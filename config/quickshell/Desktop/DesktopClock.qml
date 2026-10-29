import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services

PanelWindow {
    id: root

    // ─── ajustes rápidos ──────────────────────────────────────────────
    property int topMargin: 120
    property int dayFontSize: 64        // tamaño de las letras del día
    property real waveAmplitude: 10     // qué tanto "ondulan" las letras
    property real waveFrequency: 1.1    // qué tan rápido ondulan
    property real letterRotation: 6     // inclinación máxima por letra (grados)
    property int dateFontSize: 20
    property int timeFontSize: 26
    property string fontFamily: "Poppins"        // fuente para fecha/hora
    property string dayFontFamily: "Anurati"     // fuente del día (mond)
    property real dim: 0.95
    property bool use24h: false
    // Fondos cuyo motivo ocupa el centro: el reloj se aparta a un lado
    // ("left", "right" o una fracción 0–1 del ancho para el centro del
    // bloque, por nombre de archivo). El resto, centrado.
    property var sideForWallpaper: ({
        "astronaut-jellyfish.jpg": "left",
        "japanese1.jpg": 0.82,           // sobre el follaje oscuro, arriba a la derecha
        "iceberg-moon.png": "left"       // la luna ocupa el centro-derecha
    })
    // Margen superior propio por fondo (px); los que no estén usan topMargin.
    property var topMarginForWallpaper: ({
        "lenovowallpaper.png": 220
    })
    // ──────────────────────────────────────────────────────────────────

    readonly property string wallpaperName: Wallpaper.current.split("/").pop()
    readonly property var side: sideForWallpaper[wallpaperName] ?? "center"
    readonly property real sideFraction: typeof side === "number" ? side
        : side === "left" ? 0.25 : side === "right" ? 0.75 : 0.5
    readonly property int effectiveTopMargin: topMarginForWallpaper[wallpaperName] ?? topMargin

    property var modelData
    screen: modelData ?? null

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qs-desktop-clock"
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    mask: Region {}

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property string dayString: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
    // Anurati dibuja la "I" mayúscula como un trazo casi invisible por
    // diseño (no es un bug del layout). Se localiza para sustituirla por
    // una barra dibujada a mano más abajo. Los días en inglés tienen como
    // mucho una "I" (FRIDAY), así que un solo índice basta.
    // Solo si Anurati está instalada: con la fuente de reserva la "I" es
    // normal y la barra sustituta quedaba fina y descolocada (FRIDAY).
    readonly property bool hasDayFont: Qt.fontFamilies().indexOf(root.dayFontFamily) !== -1
    readonly property int dayIIndex: root.hasDayFont ? root.dayString.indexOf("I") : -1
    readonly property string dayBefore: root.dayIIndex >= 0 ? root.dayString.substring(0, root.dayIIndex) : root.dayString
    readonly property string dayAfter: root.dayIIndex >= 0 ? root.dayString.substring(root.dayIIndex + 1) : ""
    readonly property string dateString: Qt.formatDateTime(clock.date, "d MMMM, yyyy").toUpperCase()
    readonly property string timeString:
        Qt.formatDateTime(clock.date, root.use24h ? "HH:mm" : "hh:mm AP")

    Column {
        id: clockColumn
        // Centro del bloque en la fracción del ancho que indique 'side'.
        x: parent.width * root.sideFraction - width / 2
        Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        anchors.top: parent.top
        anchors.topMargin: root.effectiveTopMargin
        Behavior on anchors.topMargin { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        spacing: 14
        opacity: root.dim

        // ── día de la semana ──
        // Anurati tiene metrics de glifo muy inusuales (los trazos se salen
        // de su propio ancho de avance a propósito, por diseño). Componerlo
        // letra por letra en un Row rompe esas metrics y las letras se
        // solapan/comen entre sí, así que se renderiza como palabra(s)
        // completas para que el motor de texto de Qt calcule el layout.
        // La única excepción es la "I": el glifo de la fuente es casi
        // invisible a propósito, así que se sustituye por una barra dibujada
        // a mano del alto de una mayúscula.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.dayFontSize * 0.12

            Text {
                visible: root.dayBefore.length > 0
                text: root.dayBefore
                font.family: root.dayFontFamily
                font.pixelSize: root.dayFontSize
                font.weight: Font.Bold
                font.letterSpacing: root.dayFontSize * 0.12
                color: "white"
                style: Text.Outline
                styleColor: "white"   // grosor falso: contorno del mismo color rellena los trazos finos
            }

            Item {
                visible: root.dayIIndex >= 0
                width: Math.max(4, root.dayFontSize * 0.05)
                height: root.dayFontSize

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(3, root.dayFontSize * 0.09)
                    height: root.dayFontSize * 0.7
                    color: "white"
                }
            }

            Text {
                visible: root.dayAfter.length > 0
                text: root.dayAfter
                font.family: root.dayFontFamily
                font.pixelSize: root.dayFontSize
                font.weight: Font.Bold
                font.letterSpacing: root.dayFontSize * 0.12
                color: "white"
                style: Text.Outline
                styleColor: "white"
            }
        }

        // ── fecha ──
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateString
            font.family: root.fontFamily
            font.pixelSize: root.dateFontSize
            font.weight: Font.Light
            font.letterSpacing: 3
            color: "white"
            opacity: 0.85
            style: Text.Outline
            styleColor: "#40000000"
        }

        // ── hora, con guiones a los lados ──
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeString
            font.family: root.fontFamily
            font.pixelSize: root.timeFontSize
            font.weight: Font.Bold
            font.letterSpacing: 2
            color: "white"
            opacity: 0.9
            style: Text.Outline
            styleColor: "#40000000"
        }
    }
}
