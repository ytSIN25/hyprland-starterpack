pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Contraseñas de las redes WiFi guardadas (scripts/wifi-passwords.sh).
// Se leen al abrir el modal y se vacían al cerrarlo: no quedan en memoria
// del shell más tiempo del necesario.
Singleton {
    id: wp

    property bool open: false
    property bool loading: false
    // [{ name, secret, kind }] -- kind: "psk" | "eap" | "open"
    property var entries: []

    function openPanel() { open = true; refresh() }
    function closePanel() { open = false; entries = [] }

    function refresh() {
        if (proc.running) return
        loading = true
        proc.running = true
    }

    function copy(text) {
        if (text === "") return
        Quickshell.execDetached(["wl-copy", "--", text])
    }

    Process {
        id: proc
        command: ["bash", Quickshell.shellDir + "/scripts/wifi-passwords.sh", "--tsv"]
        stdout: StdioCollector {
            onStreamFinished: {
                wp.entries = text.split("\n").filter(l => l !== "").map(l => {
                    const f = l.split("\t")
                    return { name: f[0], secret: f[1] || "", kind: f[2] || "psk" }
                }).sort((a, b) => a.name.localeCompare(b.name))
                wp.loading = false
            }
        }
        onExited: wp.loading = false
    }
}
