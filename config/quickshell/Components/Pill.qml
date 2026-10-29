import QtQuick
import QtQuick.Layouts
import qs.Config

// Contenedor "pill" reutilizable. El contenido va a un GridLayout interno centrado,
// cuyo tamaño intrínseco dimensiona la pastilla (sin binding loops): en fila
// con la barra horizontal y en columna con la barra vertical (Theme.barVertical).
// Click, click derecho y rueda expuestos como señales.
//
// Lenguaje visual: superficie tonal SIN borde (el borde queda reservado al
// anillo de foco de teclado). La interacción se comunica con movimiento: la
// píldora se eleva un pelo bajo el ratón, se hunde al pulsar y muestra un
// punto de acento debajo cuando el panel que gobierna está abierto ('active').
Rectangle {
    id: pill

    property bool interactive: false
    property bool hoverHighlight: false
    property bool hoverCursor: false
    // El panel que abre esta píldora está abierto: enciende el punto inferior.
    property bool active: false
    readonly property bool hovered: ma.containsMouse || hoverHandler.hovered || activeFocus
    property int spacing: Theme.spacing
    default property alias content: row.data

    signal clicked(var mouse)
    signal rightClicked()
    signal scrolled(real dy)

    implicitWidth: Theme.barVertical ? Theme.barPillHeight : row.implicitWidth + Theme.pad * 2
    implicitHeight: Theme.barVertical ? row.implicitHeight + Theme.dp(5) * 2 : Theme.barPillHeight

    activeFocusOnTab: interactive
    // Cápsula completa (estilo saneAspect).
    radius: Math.min(width, height) / 2
    color: (interactive || hoverHighlight) && hovered ? Theme.surfaceHi : Theme.pillBg
    border.width: activeFocus ? Theme.focusWidth : 0
    border.color: Theme.focusRing

    // Elevación al pasar y hundimiento al pulsar: escala visual pura (no
    // afecta a la disposición de la barra).
    scale: ma.pressed ? 0.95
         : (interactive || hoverHighlight) && hovered ? 1.04
         : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }

    Behavior on color { ColorAnimation { duration: Theme.animFast } }

    // Punto indicador de "panel abierto": nace y muere con un pop de escala.
    // Debajo en horizontal; en vertical, en el lado que mira al escritorio.
    Rectangle {
        readonly property int edgeGap: Theme.dp(2)
        x: !Theme.barVertical ? (parent.width - width) / 2
           : Settings.barPosition === "right" ? edgeGap
           : parent.width - width - edgeGap
        y: Theme.barVertical ? (parent.height - height) / 2
           : parent.height - height - edgeGap
        width: Theme.dp(4); height: Theme.dp(4)
        radius: width / 2
        color: Theme.accent
        scale: pill.active ? 1 : 0
        opacity: pill.active ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        Behavior on opacity { NumberAnimation { duration: Theme.animFast } }
    }

    Keys.onReturnPressed: pill.clicked({ x: -999999, y: -999999, button: Qt.LeftButton })
    Keys.onEnterPressed: pill.clicked({ x: -999999, y: -999999, button: Qt.LeftButton })
    Keys.onSpacePressed: pill.clicked({ x: -999999, y: -999999, button: Qt.LeftButton })
    Keys.onEscapePressed: Globals.closeAll()

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: pill.interactive || pill.hoverCursor
        hoverEnabled: pill.interactive || pill.hoverCursor
        cursorShape: (pill.interactive || pill.hoverCursor) ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: pill.interactive ? (Qt.LeftButton | Qt.RightButton) : Qt.NoButton
        onClicked: (m) => {
            if (m.button === Qt.RightButton) pill.rightClicked()
            else pill.clicked(m)
        }
        // La rueda se gestiona aquí y no con un WheelHandler: al MouseArea le
        // llegan los eventos por propagación aunque el cursor esté sobre un
        // hijo con su propio MouseArea (los puntos de Workspaces); el handler
        // no los recibía en esa situación. Si la píldora no es interactiva, el
        // evento se deja pasar sin consumir.
        onWheel: (e) => {
            if (pill.interactive) pill.scrolled(e.angleDelta.y)
            else e.accepted = false
        }
    }

    GridLayout {
        id: row
        anchors.centerIn: parent
        flow: Theme.barVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: pill.spacing
        rowSpacing: pill.spacing

        // Centra cada hijo en el eje transversal (en columna, un layout los
        // alinea a la izquierda). Diferido: Layout.alignment asignado desde
        // JS solo surte efecto con el hijo ya completado (Repeater incluido).
        function centerChildren() {
            for (let i = 0; i < children.length; i++)
                children[i].Layout.alignment = Qt.AlignCenter
        }
        onChildrenChanged: Qt.callLater(centerChildren)
    }

    // Arrastre para reordenar (lo activa Bar/ReorderRow.qml). Vive en la
    // píldora y no en el MouseArea: el handler toma un agarre pasivo al
    // pulsar y, al superar el umbral, se lo roba al MouseArea, así que un
    // click normal sigue funcionando y un arrastre no dispara el click.
    property bool draggable: false
    readonly property alias dragHandler: dragHandler
    DragHandler {
        id: dragHandler
        enabled: pill.draggable
        target: null
        xAxis.enabled: !Theme.barVertical
        yAxis.enabled: Theme.barVertical
        cursorShape: Qt.ClosedHandCursor
    }

    HoverHandler {
        id: hoverHandler
        enabled: pill.hoverCursor || pill.hoverHighlight
        cursorShape: pill.hoverCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

}
