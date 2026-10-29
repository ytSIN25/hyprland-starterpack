pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Limpiador de disco (Panels/DiskCleanPanel.qml).
//  - scan(): scripts/disk-scan.sh mide cada categoría sin root.
//  - clean(keys): abre scripts/disk-clean.sh en kitty (sudo pide la
//    contraseña ahí y se ve qué se borra); al terminar vuelve a escanear.
//  - Espacio libre en / cada 5 min: lowSpace → aviso en la isla.
// IPC: qs ipc call disk open | rescan
Singleton {
    id: root

    // Categorías: clave → textos. 'root' = necesita sudo. 'safe' = marcada
    // por defecto. Todas se regeneran solas o se vuelven a descargar; la
    // papelera no viene marcada porque borra tus archivos para siempre.
    // Fuera a propósito: paquetes huérfanos (pueden ser cosas que usas),
    // Docker (borraría contenedores parados) y "caché antigua" genérica.
    readonly property var defs: [
        { key: "trash",      icon: "󰩺", title: I18n.tr("Trash"),            desc: I18n.tr("Files you already deleted (can't be undone)"), root: false, safe: false },
        { key: "aur",        icon: "󰏗", title: I18n.tr("AUR build files"),  desc: I18n.tr("yay/paru sources, re-downloaded when needed"), root: false, safe: true },
        { key: "pacman",     icon: "󰮯", title: I18n.tr("Package cache"),    desc: I18n.tr("Old package versions (keeps the newest 2)"),  root: true,  safe: true },
        { key: "journal",    icon: "󰈙", title: I18n.tr("System logs"),      desc: I18n.tr("Old logs, keeps the newest 100 MB"),           root: true,  safe: true },
        { key: "coredumps",  icon: "󰚌", title: I18n.tr("Crash dumps"),      desc: I18n.tr("Saved memory of crashed apps"),                root: true,  safe: true },
        { key: "dev",        icon: "󰅩", title: I18n.tr("Developer caches"), desc: I18n.tr("pip, go, npm, pnpm, cargo download caches"),   root: false, safe: true },
        { key: "thumbnails", icon: "󰋩", title: I18n.tr("Thumbnails"),       desc: I18n.tr("Image previews, rebuilt automatically"),      root: false, safe: true }
    ]

    // clave → { bytes (-1 = desconocido), count }
    property var sizes: ({})
    property bool scanning: false
    property bool scannedOnce: false
    property var selected: ({})          // clave → bool (elección del usuario)
    property bool cleaning: false

    readonly property var items: defs.filter(d => sizes[d.key] !== undefined)
                                     .map(d => Object.assign({}, d, sizes[d.key]))
    function isSelected(key) {
        return selected[key] !== undefined ? selected[key] : (defs.find(d => d.key === key)?.safe ?? false)
    }
    function toggle(key) {
        const s = Object.assign({}, selected)
        s[key] = !isSelected(key)
        root.selected = s
    }
    readonly property real selectedBytes: items.filter(i => isSelected(i.key) && i.bytes > 0)
                                               .reduce((a, i) => a + i.bytes, 0)
    readonly property real totalBytes: items.filter(i => i.bytes > 0).reduce((a, i) => a + i.bytes, 0)

    // Disco (/)
    property real diskTotal: 0
    property real diskFree: 0
    readonly property real diskUsedFrac: diskTotal > 0 ? 1 - diskFree / diskTotal : 0
    // < 10 % o < 10 GiB libres
    readonly property bool lowSpace: diskTotal > 0
        && (diskFree / diskTotal < 0.10 || diskFree < 10 * 1024 * 1024 * 1024)

    function human(b) {
        if (b < 0) return "?"
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i >= 3 ? b.toFixed(1) : Math.round(b)) + " " + u[i]
    }

    function _script(name) {
        return decodeURIComponent(Qt.resolvedUrl("../scripts/" + name).toString().replace(/^file:\/\//, ""))
    }

    function scan() {
        if (scanProc.running) return
        root.scanning = true
        scanProc.running = true
        if (!dfProc.running) dfProc.running = true
    }
    Process {
        id: scanProc
        command: ["bash", root._script("disk-scan.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {}
                for (const l of (this.text || "").split("\n")) {
                    const f = l.split("\t")
                    if (f.length < 2 || f[0] === "") continue
                    out[f[0]] = { bytes: parseFloat(f[1]) || 0, count: parseInt(f[2]) || 0 }
                }
                root.sizes = out
                root.scanning = false
                root.scannedOnce = true
            }
        }
        onExited: root.scanning = false
    }

    function clean(keys) {
        keys = keys.filter(k => sizes[k] !== undefined)
        if (keys.length === 0) return
        root.cleaning = true
        cleanProc.command = ["kitty", "--class", "qs-diskclean", "--title", "Disk cleaner",
                             "-e", "bash", _script("disk-clean.sh")].concat(keys)
        cleanProc.running = true
        Globals.closeAll()
    }
    function cleanSelected() { clean(items.filter(i => isSelected(i.key)).map(i => i.key)) }
    Process {
        id: cleanProc
        onExited: { root.cleaning = false; root.scan() }
    }

    Process {
        id: dfProc
        command: ["df", "-B1", "--output=size,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = (this.text || "").trim().split("\n").pop().trim().split(/\s+/)
                if (l.length < 2) return
                root.diskTotal = parseFloat(l[0]) || 0
                root.diskFree = parseFloat(l[1]) || 0
            }
        }
    }
    Timer {
        interval: 5 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!dfProc.running) dfProc.running = true
    }

    IpcHandler {
        target: "disk"
        function open(): void { Globals.toggle("disk") }
        function rescan(): void { root.scan() }
    }
}
