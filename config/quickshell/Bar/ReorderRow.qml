import QtQuick
import QtQuick.Layouts
import qs.Config

// Grupo de la barra cuyas píldoras se reordenan arrastrándolas. Cada hijo
// directo necesita un objectName (la clave guardada en Settings.barOrder) y
// ser una Pill o contener una (p.ej. el hueco animado de Duolingo).
// Mientras se arrastra, solo se desplazan visualmente (Translate) la píldora
// y las vecinas que le hacen hueco; al soltar se reordena de verdad. El orden
// real se cambia re-emparentando: el GridLayout coloca a sus hijos en el
// orden de 'children' y un hijo re-emparentado pasa al final (stackBefore/
// stackAfter no son invocables desde QML).
GridLayout {
    id: group

    // Clave del grupo dentro de Settings.barOrder ("start" / "end").
    required property string orderKey

    flow: Theme.barVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight

    property Item dragged: null
    property var _declared: []
    property var _shifts: ({})

    function _slots() {
        const out = []
        for (let i = 0; i < children.length; i++)
            if (children[i].objectName !== "")
                out.push(children[i])
        return out
    }

    function _handleOf(item) {
        if (item.draggable !== undefined)
            return item
        for (let i = 0; i < item.children.length; i++)
            if (item.children[i].draggable !== undefined)
                return item.children[i]
        return null
    }

    // Re-emparenta los hijos en el orden dado (lista de Items). Pasa por el
    // padre del grupo, no por null: así no salen de la ventana ni cambian de
    // visibilidad efectiva.
    function _setOrder(items) {
        const cur = _slots()
        if (items.every((it, i) => cur[i] === it))
            return
        const via = group.parent
        for (const it of items) {
            it.parent = via
            it.parent = group
        }
    }

    function applyOrder() {
        if (dragged)
            return
        const saved = (Settings.barOrder || {})[orderKey] || []
        const byName = {}
        for (const s of _slots()) byName[s.objectName] = s
        // Lo guardado que aún existe, y lo nuevo (sin guardar) en su puesto
        // declarado.
        const order = saved.filter(n => byName[n] !== undefined)
        _declared.forEach((n, i) => {
            if (order.indexOf(n) === -1 && byName[n] !== undefined)
                order.splice(Math.min(i, order.length), 0, n)
        })
        _setOrder(order.map(n => byName[n]))
    }

    function saveOrder() {
        const o = Object.assign({}, Settings.barOrder || {})
        o[orderKey] = _slots().map(s => s.objectName)
        Settings.barOrder = o
    }

    Component {
        id: shiftComp
        Translate {
            property bool animated: false
            Behavior on x { enabled: animated; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: animated; NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutCubic } }
        }
    }

    function _setShift(item, v, animated) {
        const t = _shifts[item.objectName]
        if (!t) return
        t.animated = animated
        if (Theme.barVertical) { t.x = 0; t.y = v } else { t.x = v; t.y = 0 }
    }

    // Estado del arrastre en curso.
    property var _vis: []
    property int _from: -1
    property int _to: -1

    function _dragStart(item) {
        dragged = item
        item.z = 1
        _vis = _slots().filter(s => s.visible)
        _from = _to = _vis.indexOf(item)
    }

    function _dragMove(item, t) {
        const vert = Theme.barVertical
        const pos = s => vert ? s.y : s.x
        const len = s => vert ? s.height : s.width
        const center = pos(item) + len(item) / 2 + t
        let to = 0
        for (let j = 0; j < _vis.length; j++)
            if (j !== _from && center > pos(_vis[j]) + len(_vis[j]) / 2)
                to++
        _to = to
        const gap = len(item) + (vert ? rowSpacing : columnSpacing)
        for (let j = 0; j < _vis.length; j++) {
            const s = _vis[j]
            if (s === item) _setShift(s, t, false)
            else if (j > _from && j <= _to) _setShift(s, -gap, true)
            else if (j < _from && j >= _to) _setShift(s, gap, true)
            else _setShift(s, 0, true)
        }
    }

    function _dragEnd(item) {
        const all = _slots()
        if (_to !== _from) {
            all.splice(all.indexOf(item), 1)
            const others = _vis.filter(s => s !== item)
            const at = _to < others.length ? all.indexOf(others[_to]) : all.indexOf(others[others.length - 1]) + 1
            all.splice(at, 0, item)
        }
        for (const s of _slots()) _setShift(s, 0, false)
        item.z = 0
        dragged = null
        _vis = []
        if (_to !== _from) {
            _setOrder(all)
            saveOrder()
        }
    }

    function _attach(item) {
        const handle = _handleOf(item)
        if (!handle)
            return
        handle.draggable = true
        const shift = shiftComp.createObject(item)
        item.transform = [shift]
        _shifts[item.objectName] = shift
        const dh = handle.dragHandler
        dh.activeChanged.connect(() => dh.active ? group._dragStart(item) : group._dragEnd(item))
        dh.translationChanged.connect(() => {
            if (dh.active)
                group._dragMove(item, Theme.barVertical ? dh.translation.y : dh.translation.x)
        })
    }

    Component.onCompleted: {
        const slots = _slots()
        _declared = slots.map(s => s.objectName)
        for (const s of slots) _attach(s)
        applyOrder()
    }

    // Otras barras (otro monitor) o una edición a mano de settings.json.
    Connections {
        target: Settings
        function onBarOrderChanged() { group.applyOrder() }
    }
}
