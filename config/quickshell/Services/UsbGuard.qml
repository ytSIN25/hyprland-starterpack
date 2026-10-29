pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// USBGuard: los USB nuevos llegan bloqueados y la isla pregunta
// Allow once / Always / Block. Instalación y política:
// scripts/setup-usbguard.sh (una vez, con sudo). Sin usbguard → inactivo.
//  - `usbguard watch` avisa de cada evento; tras cada uno se relee
//    `usbguard list-devices --blocked` y los bloqueados nuevos emiten blocked().
//  - Un dispositivo permitido por la política emite connected() (aviso breve).
Singleton {
    id: root

    signal blocked(int id, string name, string kind, bool suspicious)
    signal connected(string name, string kind)

    property bool available: false      // daemon activo y con permiso IPC
    property var _asked: ({})           // id → true (ya preguntado)

    // Clase USB (interfaz "cc:ss:pp") → tipo legible.
    function kindOf(ifaces) {
        const has = re => ifaces.some(i => re.test(i))
        if (has(/^03:01:01/)) return "keyboard"
        if (has(/^03:01:02/)) return "mouse"
        if (has(/^08:/)) return "storage"
        if (has(/^0e:/)) return "camera"
        if (has(/^01:/)) return "audio"
        if (has(/^e0:/)) return "bluetooth"
        if (has(/^(02|0a):/)) return "network"
        if (has(/^07:/)) return "printer"
        if (has(/^09:/)) return "hub"
        if (has(/^03:/)) return "input"
        return "device"
    }
    function kindLabel(k) {
        return ({ keyboard: "Keyboard", mouse: "Mouse", storage: "USB drive", camera: "Camera",
                  audio: "Audio", bluetooth: "Bluetooth", network: "Network adapter",
                  printer: "Printer", hub: "USB hub", input: "Input device", device: "USB device" })[k] ?? k
    }
    // "17: block id 0781:5581 serial "…" name "Ultra" hash … with-interface { 08:06:50 }"
    function _parse(line) {
        const m = line.match(/^\s*(\d+):\s+(allow|block|reject)\s+id\s+(\S+)/)
        if (!m) return null
        const name = (line.match(/\bname\s+"([^"]*)"/) || [])[1] || ""
        let ifs = []
        const g = line.match(/with-interface\s+\{([^}]*)\}/)
        if (g) ifs = g[1].trim().split(/\s+/)
        else { const one = line.match(/with-interface\s+(\S+)/); if (one) ifs = [one[1]] }
        const kind = kindOf(ifs)
        // Teclado que además es almacenamiento o red: típico de un BadUSB.
        const suspicious = ifs.some(i => /^03:01:01/.test(i)) && ifs.some(i => /^(08|02|0a|e0):/.test(i))
        return { id: parseInt(m[1]), target: m[2], usbId: m[3], name: name || m[3], kind: kind, suspicious: suspicious }
    }

    function answer(id, choice) {
        if (choice === "allow") Quickshell.execDetached(["usbguard", "allow-device", String(id)])
        else if (choice === "always") Quickshell.execDetached(["usbguard", "allow-device", "-p", String(id)])
        // "block" / sin respuesta: se queda bloqueado (no hace falta nada).
    }

    // ── Eventos ─────────────────────────────────────────────────────────────
    property string _event: ""
    Process {
        id: watch
        command: ["usbguard", "watch"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("[IPC] Connected") !== -1) { root.available = true; listDelay.restart(); return }
                let m
                if ((m = line.match(/^\s*event=(\S+)/))) { root._event = m[1]; return }
                if ((m = line.match(/^\s*device_rule=(.*)$/))) {
                    if (root._event === "Insert" && /^allow\b/.test(m[1])) {
                        const d = root._parse("0: " + m[1])
                        if (d && d.kind !== "hub") root.connected(d.name, d.kind)
                    }
                    root._event = ""
                    listDelay.restart()
                }
            }
        }
        onExited: { root.available = false; retry.start() }
    }
    // Arranque: solo si usbguard está instalado.
    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v usbguard >/dev/null && systemctl is-active -q usbguard"]
        onExited: (code) => { if (code === 0) watch.running = true; else retry.start() }
    }
    Timer {
        id: retry
        interval: 30000
        onTriggered: if (!watch.running && !probe.running) probe.running = true
    }

    Timer {
        id: listDelay
        interval: 300
        onTriggered: if (!list.running) list.running = true
    }
    Process {
        id: list
        command: ["usbguard", "list-devices", "--blocked"]
        stdout: StdioCollector {
            onStreamFinished: {
                const asked = Object.assign({}, root._asked)
                const present = {}
                for (const l of (this.text || "").split("\n")) {
                    const d = root._parse(l)
                    if (!d) continue
                    present[d.id] = true
                    if (asked[d.id]) continue
                    asked[d.id] = true
                    root.blocked(d.id, d.name, d.kind, d.suspicious)
                }
                // Los ids no se reutilizan, pero se limpia lo que ya no está.
                for (const id in asked) if (!present[id]) delete asked[id]
                root._asked = asked
            }
        }
    }
}
