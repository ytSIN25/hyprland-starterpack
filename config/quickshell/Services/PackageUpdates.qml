pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Tracks pending pacman / AUR (yay) / Flatpak updates and lets you install
// one package — or everything — from the bar. Updates run in a real kitty
// terminal so sudo/AUR prompts work exactly like running it by hand.
Singleton {
    id: pu

    property bool loading: false
    property bool checkedOnce: false
    property var  packages: []   // [{ source, name, oldVer, newVer }]
    readonly property int  count: packages.length
    property bool hasYay: false
    property bool hasFlatpak: false
    property bool hasCheckupdates: false

    function refresh() {
        if (loading) return
        loading = true
        checkProc.running = true
    }

    function _script() {
        return [
            "hascu=0; command -v checkupdates >/dev/null 2>&1 && hascu=1",
            "hasyay=0; command -v yay >/dev/null 2>&1 && hasyay=1",
            "hasflatpak=0; command -v flatpak >/dev/null 2>&1 && hasflatpak=1",
            "echo \"__HAS__ $hascu $hasyay $hasflatpak\"",
            "if [ \"$hascu\" = 1 ]; then",
            "  checkupdates 2>/dev/null | awk '{print \"pacman|\"$1\"|\"$2\"|\"$4}'",
            "fi",
            "if [ \"$hasyay\" = 1 ]; then",
            "  yay -Qua 2>/dev/null | awk '{print \"aur|\"$1\"|\"$2\"|\"$4}'",
            "fi",
            "if [ \"$hasflatpak\" = 1 ]; then",
            "  flatpak remote-ls --updates --columns=application,version 2>/dev/null | " +
                "awk -F'\\t' 'NF>=1 && $1!=\"Application\" {print \"flatpak|\"$1\"|-|\"$2}'",
            "fi"
        ].join("\n")
    }

    Process {
        id: checkProc
        command: ["sh", "-c", pu._script()]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").map(l => l.trim()).filter(l => l !== "")
                const list = []
                let hascu = false, hasyay = false, hasflatpak = false
                for (const line of lines) {
                    if (line.indexOf("__HAS__") === 0) {
                        const p = line.split(" ")
                        hascu = p[1] === "1"
                        hasyay = p[2] === "1"
                        hasflatpak = p[3] === "1"
                        continue
                    }
                    const parts = line.split("|")
                    if (parts.length < 4) continue
                    list.push({ source: parts[0], name: parts[1], oldVer: parts[2], newVer: parts[3] })
                }
                pu.hasCheckupdates = hascu
                pu.hasYay = hasyay
                pu.hasFlatpak = hasflatpak
                pu.packages = list
                pu.loading = false
                pu.checkedOnce = true
            }
        }
    }

    function updatePackage(pkg) {
        let cmd
        if (pkg.source === "aur") cmd = "yay -S " + pkg.name
        else if (pkg.source === "flatpak") cmd = "flatpak update -y " + pkg.name
        else cmd = "sudo pacman -S " + pkg.name
        _runInTerminal(cmd)
    }

    function updateAll() {
        const cmds = []
        cmds.push(pu.hasYay ? "yay -Syu" : "sudo pacman -Syu")
        if (pu.hasFlatpak) cmds.push("flatpak update -y")
        _runInTerminal(cmds.join(" && "))
    }

    function _runInTerminal(cmd) {
        termProc.command = ["kitty", "--hold", "-e", "bash", "-c", cmd]
        termProc.running = true
    }

    // Cuando se cierra la ventana de kitty (update terminado / cancelado),
    // se refresca la lista.
    Process {
        id: termProc
        onExited: pu.refresh()
    }

    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pu.refresh()
    }
}
