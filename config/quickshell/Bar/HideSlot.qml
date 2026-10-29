import QtQuick
import QtQuick.Layouts
import qs.Config

// Hueco de un widget de la barra que puede estar oculto (Ajustes → Barra →
// "Hidden"): un widget oculto solo aparece con SUPER+SHIFT+D. El hueco
// crece/encoge animado y la píldora funde y escala, en vez de aparecer de golpe.
// 'cond' es la condición propia del widget (ajuste activado, hay algo que
// mostrar…); no se lee 'visible' del hijo porque depende del propio hueco.
Item {
    id: slot
    property bool cond: true
    readonly property Item w: children.length > 0 ? children[0] : null
    readonly property bool shown: cond && (!Settings.isWidgetHidden(objectName) || Globals.showHiddenIcons)
    property real t: shown ? 1 : 0
    Behavior on t { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
    visible: t > 0
    clip: t < 1
    Layout.alignment: Qt.AlignCenter
    Layout.preferredWidth: !w ? 0 : Theme.barVertical ? w.implicitWidth : w.implicitWidth * t
    Layout.preferredHeight: !w ? 0 : Theme.barVertical ? w.implicitHeight * t : w.implicitHeight

    // Fundido y escala en el hueco, no en la píldora: su 'scale' es el rebote al pulsar.
    opacity: t
    scale: 0.6 + 0.4 * t
    onWChanged: if (w) w.anchors.centerIn = slot
}
