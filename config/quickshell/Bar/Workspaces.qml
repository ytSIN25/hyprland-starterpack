import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Components
import qs.Config

// Workspaces de Hyprland: el activo se ensancha, se ilumina y muestra su
// número. Click en un punto salta a ese workspace; la rueda sobre la píldora
// recorre los workspaces de esta pantalla en orden.
Pill {
    id: root
    property var screen
    interactive: true
    hoverCursor: true

    // Siempre se muestran workspaceCount puntos (1..N), existan ya en
    // Hyprland o no, así la píldora no cambia de ancho ni deja huecos al
    // crear workspaces nuevos. Se completa con los datos reales (activo,
    // etc.) cuando el workspace ya existe.
    readonly property int workspaceCount: 5

    readonly property var wsList: {
        const real = Hyprland.workspaces.values
            .filter(w => !w.monitor || !root.screen || w.monitor.name === root.screen.name)
        const byId = {}
        for (const w of real) byId[w.id] = w
        const list = []
        for (let i = 1; i <= workspaceCount; i++)
            list.push(byId[i] ?? { id: i, active: false, lastIpcObject: null })
        return list
    }

    function focusWorkspace(workspace) {
        const id = workspace && workspace.id !== undefined ? workspace.id : 1
        // En modo Lua, dispatch() se interpreta como hl.dispatch(...), así
        // que "workspace N" petaría con error de sintaxis. Hay que usar la
        // API Lua (hl.dsp.focus).
        if (Hyprland.usingLua) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
        } else {
            Hyprland.dispatch("workspace " + id)
        }
    }

    // Salta al workspace numérico vecino (dir = ±1), acotado a 1..workspaceCount.
    function step(dir) {
        const cur = wsList.find(w => w.active)
        const base = cur ? cur.id : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1)
        const target = Math.max(1, Math.min(workspaceCount, base + dir))
        if (target !== base)
            focusWorkspace({ id: target })
    }

    onScrolled: (dy) => step(dy > 0 ? -1 : 1)

    Repeater {
        model: ScriptModel { values: root.wsList }

        delegate: Rectangle {
            id: ws
            required property var modelData

            readonly property bool active: modelData ? modelData.active : false

            // El activo se alarga en el eje de la barra (alto si es vertical).
            readonly property int longSide: active ? Theme.dp(30) : Theme.dp(13)
            implicitWidth: Theme.barVertical ? Theme.dp(13) : longSide
            implicitHeight: Theme.barVertical ? longSide : Theme.dp(13)
            radius: Math.min(width, height) / 2
            // Crece un pelo bajo el ratón y nace con un pop al crearse.
            scale: wsMa.containsMouse && !active ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Component.onCompleted: { scale = 0.4; scale = Qt.binding(() =>
                wsMa.containsMouse && !ws.active ? 1.25 : 1) }

            color: active ? Theme.accent
                 : wsMa.containsMouse ? Theme.withAlpha(Theme.accent, 0.45)
                 : Theme.overlay

            Behavior on implicitWidth {
                NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
            Behavior on implicitHeight {
                NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic }
            }
            Behavior on color { ColorAnimation { duration: Theme.animFast } }

            Text {
                anchors.centerIn: parent
                visible: ws.active
                text: ws.modelData ? ws.modelData.id : ""
                color: Theme.bg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sp(11)
                font.bold: true
            }

            MouseArea {
                id: wsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWorkspace(ws.modelData)
            }
        }
    }
}
