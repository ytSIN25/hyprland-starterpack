pragma ComponentBehavior: Bound
// Workstation mode for Quickshell + Hyprland.
// Toggle: `qs ipc call workstation toggle` (e.g. Ctrl+Super+Tab, 3-finger swipe up).
// The focused window shrinks (live preview) into the lower part of the screen;
// the other open windows appear above it. Click one to jump to it. With more
// than `stackThreshold` windows they fan out into a stack and the hovered one
// stands out. Esc, clicking the backdrop or the current window → go back.
// A visible scratchpad (special workspace) is hidden on open, and scratchpad
// windows are never shown.
// Works with both Hyprland config styles (Lua and classic hyprlang).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: plugin

    // ── Look & tuning (wire these to your own theme if you have one) ─────
    property color accent: "#7aa2f7"       // hovered card border
    property color surface: "#1e2030"      // card background while the preview loads
    property string fontFamily: "sans-serif"
    property int stackThreshold: 3         // more windows than this → stacked fan
    property real splitRatio: 0.4          // top/bottom split (lower = bigger main window)
    property real topInset: 64             // space kept free at the top (bar height)

    property bool open: false
    property bool _switching: false        // jumping to another window: fade only
    property var  current: null            // { addr, cls, title, x, y, w, h, tl }
    property var  others: []
    property int  hovered: -1
    property var  _screen: null
    property var  _pending: null

    // 0 → window at its real size, 1 → shrunk into the lower area
    property real t: open ? 1 : 0
    Behavior on t { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    readonly property bool _lua: Hyprland.usingLua === true

    function _bare(addr) { return String(addr || "").replace(/^0x/, "") }
    function _toplevel(addr) {
        const a = _bare(addr)
        return Hyprland.toplevels.values.find(t => _bare(t.address) === a) ?? null
    }
    function iconFor(cls) {
        if (!cls) return ""
        const e = DesktopEntries.heuristicLookup(cls)
        return Quickshell.iconPath(e?.icon || cls, true)
    }

    function toggle() { open ? close() : snapshot.running = true }
    function close() { _switching = false; open = false; hovered = -1 }

    function activate(i) {
        const w = others[i]
        if (!w) return
        _pending = w
        _switching = true
        open = false
        hovered = -1
        // When the overlay releases exclusive keyboard focus, Hyprland hands
        // focus back to the previous window, so the jump happens right after.
        focusLater.restart()
    }
    Timer {
        id: focusLater
        interval: 60
        onTriggered: {
            const w = plugin._pending
            plugin._pending = null
            if (!w) return
            const addr = "0x" + plugin._bare(w.addr)
            Hyprland.dispatch(plugin._lua
                ? 'hl.dsp.focus({ window = "address:' + addr + '" })'
                : "focuswindow address:" + addr)
        }
    }

    // Fresh Hyprland state in one call (geometry, focus, monitor). If a
    // scratchpad is visible on the focused monitor it is hidden first.
    Process {
        id: snapshot
        command: ["sh", "-c",
            'sp=$(hyprctl -j monitors | jq -r \'.[] | select(.focused) | .specialWorkspace.name // ""\'); '
            + 'if [ -n "$sp" ]; then '
            + '  if [ "$1" = lua ]; then hyprctl dispatch "hl.dsp.workspace.toggle_special(\\"${sp#special:}\\")" >/dev/null; '
            + '  else hyprctl dispatch togglespecialworkspace "${sp#special:}" >/dev/null; fi; '
            + '  sleep 0.05; '
            + 'fi; '
            + 'printf \'{"clients":%s,"active":%s,"monitors":%s}\' '
            + '"$(hyprctl -j clients)" "$(hyprctl -j activewindow)" "$(hyprctl -j monitors)"',
            "sh", plugin._lua ? "lua" : "conf"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try { d = JSON.parse(this.text) } catch (e) { console.warn("Workstation: bad hyprctl output"); return }
                const mon = (d.monitors || []).find(m => m.focused) || (d.monitors || [])[0]
                if (!mon) return
                const scr = Quickshell.screens.find(s => s.name === mon.name) || Quickshell.screens[0]
                const toWin = c => ({
                    addr: c.address, cls: c.class || "", title: c.title || "",
                    x: c.at[0] - mon.x, y: c.at[1] - mon.y, w: c.size[0], h: c.size[1],
                    tl: plugin._toplevel(c.address)
                })
                // Scratchpad windows (special workspaces, id < 0) are ignored.
                const act = d.active && d.active.address && d.active.workspace?.id > 0 ? d.active.address : ""
                plugin.current = act !== "" ? toWin(d.active) : null
                plugin.others = (d.clients || [])
                    .filter(c => c.mapped && !c.hidden && c.address !== act && c.size[0] > 0
                                 && c.workspace?.id > 0)
                    .sort((a, b) => a.focusHistoryID - b.focusHistoryID)   // most recent first
                    .map(toWin)
                plugin._screen = scr
                plugin._switching = false
                plugin.hovered = -1
                plugin.open = true
            }
        }
    }

    IpcHandler {
        target: "workstation"
        function toggle(): void { plugin.toggle() }
        function hide(): void { plugin.close() }
    }

    PanelWindow {
        id: win
        screen: plugin._screen
        visible: plugin._screen !== null && (plugin.open || plugin.t > 0.002)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-workstation"
        WlrLayershell.keyboardFocus: plugin.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }

        Connections {
            target: plugin
            function onOpenChanged() { if (plugin.open) Qt.callLater(root.forceActiveFocus) }
        }

        Item {
            id: root
            anchors.fill: parent
            focus: true
            opacity: plugin._switching ? plugin.t : 1

            readonly property real margin: 40
            readonly property real midGap: 14
            readonly property real split: height * plugin.splitRatio
            readonly property real topY: plugin.topInset
            readonly property real topH: split - midGap - topY
            readonly property real botY: split + midGap
            readonly property real botH: height - botY - 34

            Keys.onPressed: (e) => {
                const n = plugin.others.length
                if (e.key === Qt.Key_Escape) { plugin.close(); e.accepted = true }
                else if (n > 0 && (e.key === Qt.Key_Right || e.key === Qt.Key_Tab || e.key === Qt.Key_L)) {
                    plugin.hovered = (plugin.hovered + 1) % n; e.accepted = true
                } else if (n > 0 && (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || e.key === Qt.Key_H)) {
                    plugin.hovered = plugin.hovered <= 0 ? n - 1 : plugin.hovered - 1; e.accepted = true
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                    if (plugin.hovered >= 0) plugin.activate(plugin.hovered); else plugin.close()
                    e.accepted = true
                }
            }

            // Backdrop; clicking it goes back to the current window.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.9)
                opacity: plugin.t
                MouseArea { anchors.fill: parent; onClicked: plugin.close() }
            }

            // ── Current window: from its real geometry to the lower area ─────
            Item {
                id: cur
                readonly property var w: plugin.current
                readonly property real aspect: w ? w.w / Math.max(1, w.h) : 16 / 10
                readonly property real tw: Math.min(root.width - 2 * root.margin, root.botH * aspect)
                readonly property real th: tw / aspect
                readonly property real tx: (root.width - tw) / 2
                readonly property real ty: root.botY + (root.botH - th) / 2
                readonly property real k: plugin._switching ? 1 : plugin.t
                visible: w !== null
                x: w ? w.x + (tx - w.x) * k : 0
                y: w ? w.y + (ty - w.y) * k : 0
                width: w ? w.w + (tw - w.w) * k : 0
                height: w ? w.h + (th - w.h) * k : 0

                ClippingRectangle {
                    anchors.fill: parent
                    radius: 10 + 6 * cur.k
                    color: plugin.surface
                    border.width: 2
                    border.color: Qt.rgba(1, 1, 1, 0.14 * cur.k)
                    ScreencopyView {
                        anchors.fill: parent
                        captureSource: win.visible ? (cur.w?.tl?.wayland ?? null) : null
                        live: true
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: plugin.close() }
            }
            Text {
                visible: plugin.current === null
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.botY + root.botH / 2 - height / 2
                text: "No focused window"
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: plugin.fontFamily
                font.pixelSize: 18
                opacity: plugin.t
            }

            // ── Other windows (upper area) ───────────────────────────────────
            Text {
                visible: plugin.others.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.topY + root.topH / 2 - height / 2
                text: "No other windows"
                color: Qt.rgba(1, 1, 1, 0.5)
                font.family: plugin.fontFamily
                font.pixelSize: 18
                opacity: plugin.t
            }

            Item {
                id: top
                x: 0; y: root.topY
                width: root.width; height: root.topH
                readonly property int n: plugin.others.length
                readonly property bool stacked: n > plugin.stackThreshold
                readonly property real labelH: 30
                // Stack: shared card height and step between cards.
                readonly property real sH: height - labelH - 12
                readonly property real avgW: {
                    if (n === 0) return 0
                    let s = 0
                    for (const w of plugin.others) s += Math.min(2.2, w.w / Math.max(1, w.h)) * sH
                    return s / n
                }
                readonly property real sStep: n > 1
                    ? Math.min(avgW * 0.62, (width - 2 * root.margin - avgW) / (n - 1)) : 0

                Repeater {
                    model: plugin.others
                    delegate: Item {
                        id: card
                        required property var modelData
                        required property int index
                        readonly property var w: modelData
                        readonly property real aspect: Math.min(2.2, w.w / Math.max(1, w.h))
                        readonly property bool hot: plugin.hovered === index
                        readonly property real mid: (top.n - 1) / 2
                        readonly property real off: index - mid

                        // Row layout (≤ threshold): one cell per window, fitted to its ratio.
                        readonly property real cellW: (top.width - 2 * root.margin - (top.n - 1) * 24) / Math.max(1, top.n)
                        readonly property real rowW: Math.min(cellW, (top.height - top.labelH) * aspect)
                        readonly property real rowH: rowW / aspect

                        width: top.stacked ? top.sH * aspect : rowW
                        height: top.stacked ? top.sH : rowH
                        x: top.stacked
                            ? top.width / 2 + off * top.sStep - width / 2
                            : root.margin + index * (cellW + 24) + (cellW - rowW) / 2
                        y: (top.stacked ? (top.height - top.labelH - height) / 2 + off * off * 3
                                        : (top.height - top.labelH - height) / 2)
                           - (hot ? 14 : 0) - (1 - plugin.t) * 40
                        rotation: top.stacked && !hot ? Math.max(-10, Math.min(10, off * 3)) : 0
                        scale: hot ? (top.stacked ? 1.14 : 1.05) : 1
                        z: hot ? 1000 : index
                        opacity: plugin.t
                        Behavior on scale    { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        // Simple shadow
                        Rectangle {
                            anchors.fill: shot
                            anchors.margins: -6
                            anchors.topMargin: 2
                            anchors.bottomMargin: -12
                            radius: shot.radius + 6
                            color: Qt.rgba(0, 0, 0, card.hot ? 0.55 : 0.35)
                        }
                        ClippingRectangle {
                            id: shot
                            anchors.fill: parent
                            radius: 14
                            color: plugin.surface
                            border.width: card.hot ? 3 : 1
                            border.color: card.hot ? plugin.accent : Qt.rgba(1, 1, 1, 0.12)
                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: win.visible ? (card.w.tl?.wayland ?? null) : null
                                live: true
                            }
                            // No capture available (no toplevel handle): show the app icon.
                            Image {
                                anchors.centerIn: parent
                                visible: !card.w.tl
                                width: Math.min(parent.width, parent.height) * 0.35
                                height: width
                                sourceSize: Qt.size(128, 128)
                                source: plugin.iconFor(card.w.cls)
                            }
                            // Stack: non-hovered cards are darkened (not made transparent).
                            Rectangle {
                                anchors.fill: parent
                                color: "black"
                                opacity: top.stacked && plugin.hovered >= 0 && !card.hot ? 0.4 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: plugin.hovered = card.index
                            onExited: if (plugin.hovered === card.index) plugin.hovered = -1
                            onClicked: plugin.activate(card.index)
                        }

                        // Label under every card (row) or only the hovered one (stack).
                        Row {
                            visible: !top.stacked || card.hot
                            anchors.top: parent.bottom
                            anchors.topMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            rotation: -card.rotation
                            Image {
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                sourceSize: Qt.size(36, 36)
                                source: plugin.iconFor(card.w.cls)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, Math.max(card.width, 260) - 26)
                                elide: Text.ElideRight
                                text: card.w.title !== "" ? card.w.title : card.w.cls
                                color: card.hot ? "white" : Qt.rgba(1, 1, 1, 0.75)
                                font.family: plugin.fontFamily
                                font.pixelSize: 14
                                font.bold: card.hot
                            }
                        }
                    }
                }
            }
        }
    }
}
