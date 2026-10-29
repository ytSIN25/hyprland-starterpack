pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Firewall state for FirewallWidget / FirewallPanel.
// Data comes from ~/.local/bin/qs-netwatch (JSON snapshot); polled every 5 s
// while the panel is open, every 20 s otherwise.
// Firewall on/off: systemctl qs-firewall.service (polkit rule
// 51-qs-firewall.rules lets this user do it without a password).
Singleton {
    id: fw

    property string firewall: "missing"     // active | inactive | missing | ...
    property bool firewallInstalled: false
    property string rootlock: "off"          // off | armed | locked | unlocked
    property real rootlockUntil: 0           // epoch s, while "unlocked" from the island
    property var inbound: []
    property var listening: []
    property var blocked: []                // dropped packets, newest first
    property bool loaded: false

    readonly property bool firewallOn: firewall === "active"
    property bool fwBusy: false

    function refresh() {
        if (!netProc.running) netProc.running = true
    }

    // ── New open ports ──────────────────────────────────────────────────────
    // Ports the user has trusted ("proto/port"), saved in trustFile. Anything
    // listening that isn't trusted is "new": badge on the pill + one desktop
    // notification. The first run trusts whatever is open at that moment.
    // Ephemeral ports (32768-60999) are skipped: client UDP sockets and
    // randomized ports (Tailscale peerapi, WebRTC...) live there and churn.
    readonly property string trustFile: Settings.home + "/.local/state/quickshell/trusted-ports.json"
    property var trusted: null              // null until trustFile has been read
    property bool trustMissing: false
    property var notified: ({})
    function portKey(l) { return l.proto + "/" + l.port }
    function ephemeral(l) { const p = parseInt(l.port, 10); return p >= 32768 && p <= 60999 }
    readonly property var newPorts: trusted === null ? []
        : listening.filter(l => !ephemeral(l) && trusted.indexOf(portKey(l)) < 0)
    function isNewPort(l) { return newPorts.some(n => portKey(n) === portKey(l)) }

    function trustPort(l) { saveTrusted(trusted.concat([portKey(l)])) }
    function trustAll()   { saveTrusted(trusted.concat(newPorts.map(portKey))) }
    function saveTrusted(list) {
        trusted = list.filter((k, i) => list.indexOf(k) === i).sort()
        saveProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"',
                            "sh", trustFile, JSON.stringify(trusted)]
        saveProc.running = true
    }
    function checkNewPorts() {
        if (trusted === null || !loaded) return
        if (trustMissing) {
            trustMissing = false
            saveTrusted(listening.filter(l => !ephemeral(l)).map(portKey))
            return
        }
        for (const l of newPorts) {
            const k = portKey(l)
            if (notified[k]) continue
            notified[k] = true
            Quickshell.execDetached(["notify-send", "-a", "Quickshell", "-u", "critical", "-i", "dialog-warning",
                I18n.tr("New open port"),
                l.proto.toUpperCase() + " " + l.port + (l.process ? " (" + l.process + ")" : "")
                + " · " + l.addr])
        }
    }

    Process {
        id: trustReadProc
        running: true
        command: ["cat", fw.trustFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = null
                try { list = JSON.parse(this.text) } catch (e) {}
                fw.trustMissing = !Array.isArray(list)
                fw.trusted = Array.isArray(list) ? list : []
                fw.checkNewPorts()
            }
        }
    }
    Process { id: saveProc }

    // Cut an SSH login off ("Connected now" → Disconnect). loginctl lets a user
    // end their own sessions without a password; e.session comes from qs-netwatch.
    signal sshDisconnected(string ip)
    function disconnect(e) {
        if (!e.session || discProc.running) return
        discProc.ip = e.ip
        discProc.command = ["loginctl", "terminate-session", e.session]
        discProc.running = true
    }
    Process {
        id: discProc
        property string ip: ""
        stderr: StdioCollector { id: discErr }
        onExited: (code) => {
            fw.refresh()
            if (code === 0) fw.sshDisconnected(ip)
            else Quickshell.execDetached(["notify-send", "-a", "Quickshell", "SSH",
                "Could not disconnect " + ip + ": " + (discErr.text.trim() || "exit code " + code)])
        }
    }

    // Close a root unlock early (panel → Lock now)
    function relock() {
        if (!relockProc.running) relockProc.running = true
    }
    Process {
        id: relockProc
        command: ["sudo", "-n", "/usr/local/sbin/qs-rootlock-allow", "revoke"]
        onExited: fw.refresh()
    }

    // Open root for `min` minutes with your password (island prompt or panel).
    // `from` comes back in unlockResult so each caller only handles its own.
    // code: 0 ok · 10 wrong password · 11 not from this desktop · other = error
    signal unlockResult(int code, string err, string from)
    readonly property bool unlockBusy: unlockProc.running
    function unlockRoot(pw, min, from) {
        if (unlockProc.running || pw === "") return false
        unlockProc._pw = pw
        unlockProc.from = from
        unlockProc.command = ["sudo", "-n", "/usr/local/sbin/qs-rootlock-allow", "allow", String(min)]
        unlockProc.running = true
        return true
    }
    Process {
        id: unlockProc
        property string _pw: ""
        property string from: ""
        stdinEnabled: true
        stderr: StdioCollector { id: unlockErr }
        onStarted: { write(_pw + "\n"); _pw = ""; stdinEnabled = false }
        onExited: (code) => {
            stdinEnabled = true
            fw.refresh()
            fw.unlockResult(code, unlockErr.text.trim().split("\n").pop(), from)
        }
    }

    function toggleFirewall() {
        if (fwBusy || !firewallInstalled) return
        fwBusy = true
        fwProc.command = ["systemctl", "--no-ask-password", firewallOn ? "stop" : "start", "qs-firewall"]
        fwProc.running = true
    }

    Process {
        id: netProc
        command: [Settings.home + "/.local/bin/qs-netwatch"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d
                try { d = JSON.parse(this.text) } catch (e) { return }
                fw.firewall = d.firewall
                fw.firewallInstalled = d.firewall_installed
                fw.rootlock = d.rootlock || "off"
                fw.rootlockUntil = d.rootlock_until || 0
                fw.inbound = d.inbound || []
                fw.listening = d.listening || []
                fw.blocked = d.blocked || []
                fw.loaded = true
                fw.checkNewPorts()
            }
        }
    }

    Process {
        id: fwProc
        stderr: StdioCollector { id: fwErr }
        onExited: (code) => {
            fw.fwBusy = false
            fw.refresh()
            if (code !== 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "Firewall",
                    "Could not toggle the firewall: " + (fwErr.text.trim() || "exit code " + code)])
        }
    }

    Timer {
        interval: Globals.firewallOpen ? 5000 : 20000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fw.refresh()
    }
    Connections {
        target: Globals
        function onFirewallOpenChanged() { if (Globals.firewallOpen) fw.refresh() }
    }
}
