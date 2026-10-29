import QtQuick
import Quickshell
import qs.Config

// Popup con el menú contextual de un item del tray, con el estilo del tema.
// Se ancla bajo el icono y se cierra al hacer click fuera (grabFocus).
PopupWindow {
    id: menu

    property var menuHandle: null
    required property var anchorItem

    // Se abre hacia el escritorio: con la barra abajo, ARRIBA del icono;
    // con la barra a un lado, al lado contrario.
    readonly property string _side: Settings.barPosition === "bottom" ? "up"
                                  : Settings.barPosition === "left" ? "right"
                                  : Settings.barPosition === "right" ? "left"
                                  : "down"
    readonly property int _edge: _side === "up" ? Edges.Top
                               : _side === "right" ? Edges.Right
                               : _side === "left" ? Edges.Left
                               : Edges.Bottom
    anchor.item: anchorItem
    anchor.edges: _edge
    anchor.gravity: _edge
    anchor.margins.top: _side === "down" ? Theme.space6 : 0
    anchor.margins.bottom: _side === "up" ? Theme.space6 : 0
    anchor.margins.left: _side === "right" ? Theme.space6 : 0
    anchor.margins.right: _side === "left" ? Theme.space6 : 0

    color: "transparent"
    visible: false
    grabFocus: true

    readonly property int pad: Theme.space6
    readonly property int minW: Theme.dp(170)
    readonly property int maxW: Theme.dp(380)

    implicitWidth: Math.max(minW, Math.min(maxW, rootLevel.implicitWidth + pad * 2))
    implicitHeight: rootLevel.implicitHeight + pad * 2

    function open() { menu.visible = true }
    function close() { menu.visible = false }

    // Al cerrar, vuelve al nivel raíz del menú.
    onVisibleChanged: if (!visible) rootLevel.reset()

    Rectangle {
        anchors.fill: parent
        radius: Theme.barRadius
        color: Theme.popupBg
        border.width: Theme.hairline
        border.color: Theme.withAlpha(Theme.overlay, 0.5)
        antialiasing: true

        MenuLevel {
            id: rootLevel
            x: menu.pad
            y: menu.pad
            width: parent.width - menu.pad * 2
            menuHandle: menu.menuHandle
            onRequestClose: menu.close()
        }
    }
}
