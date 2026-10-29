pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// IPs bloqueadas en el firewall del shell (sets blocked4/blocked6). Las
// cambia /usr/local/sbin/qs-fw-block por sudo sin contraseña (lo instala
// scripts/install-fw-block.sh). Cada bloqueo caduca solo; recargar el
// firewall los vacía.
Singleton {
    id: root

    // [{ ip, expires (epoch ms) }], el que caduca antes primero
    property var blocked: []
    readonly property string helper: "/usr/local/sbin/qs-fw-block"
    property bool installed: false
    property var _queue: []             // órdenes esperando a que acabe la anterior

    function block(ip, minutes) { _run(["add", ip, String(minutes)]) }
    function unblock(ip) { _run(["del", ip]) }
    function isBlocked(ip) { return blocked.some(b => b.ip === ip) }
    function refresh() { if (installed && !listProc.running) listProc.running = true }

    function _run(args) {
        root._queue = _queue.concat([args])
        _next()
    }
    function _next() {
        if (cmdProc.running || _queue.length === 0) return
        cmdProc.args = _queue[0]
        root._queue = _queue.slice(1)
        cmdProc.command = ["sudo", "-n", helper].concat(cmdProc.args)
        cmdProc.running = true
    }

    Process {
        id: cmdProc
        property var args: []
        stderr: StdioCollector { id: cmdErr }
        onExited: (code) => {
            if (code === 0) root.installed = true
            if (code !== 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "Firewall",
                    "Could not " + (args[0] === "add" ? "block " : "unblock ") + args[1] + ": "
                    + (cmdErr.text.trim() || "exit code " + code)])
            root.refresh()
            root._next()
        }
    }

    Process {
        id: listProc
        command: ["sudo", "-n", root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now(), out = []
                for (const l of this.text.split("\n")) {
                    const f = l.trim().split(/\s+/)
                    if (f.length === 2 && f[0] !== "") out.push({ ip: f[0], expires: now + Number(f[1]) * 1000 })
                }
                out.sort((a, b) => a.expires - b.expires)
                root.blocked = out
            }
        }
    }

    Process {
        running: true
        command: ["test", "-x", root.helper]
        onExited: (code) => { root.installed = code === 0; root.refresh() }
    }

    // Caducan solos en el kernel; se relee de vez en cuando para quitarlos
    Timer {
        interval: 30000
        running: root.installed && root.blocked.length > 0
        repeat: true
        onTriggered: root.refresh()
    }
}
