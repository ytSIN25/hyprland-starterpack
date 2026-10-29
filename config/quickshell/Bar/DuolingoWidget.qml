import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// Píldora de Duolingo: logo + racha real. Logo a color si ya se practicó hoy.
// Click muestra/oculta el panel de Duolingo, click derecho refresca.
Pill {
    id: root
    interactive: true
    active: Duolingo.panelOpen
    onClicked: Duolingo.toggle()
    onRightClicked: Duolingo.refresh()

    Image {
        source: Qt.resolvedUrl("../Assets/duolingo.png")
        sourceSize: Qt.size(Theme.barIconSize * 2, Theme.barIconSize * 2)
        Layout.preferredWidth: Theme.barIconSize
        Layout.preferredHeight: Theme.barIconSize
        opacity: !Duolingo.ok || Duolingo.practicedToday ? 1 : 0.5
        smooth: true
    }
    // Sin usuario configurado: solo el logo.
    Text {
        visible: Duolingo.ok
        text: "󰈸" + Duolingo.streak   // md-fire
        color: Duolingo.practicedToday ? Theme.orange : Theme.fgMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
}
