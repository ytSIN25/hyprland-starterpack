pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// MAC address randomization for the active WiFi connection (shown in
// WifiDetail). NetworkManager's 802-11-wireless.cloned-mac-address:
//   "off"    -> permanent  (real hardware MAC)
//   "stable" -> stable     (random per network, same every time you join it;
//                           best for networks that register your device)
//   "random" -> random     (new MAC on every connection)
// Changing it reconnects so the new address takes effect.
Singleton {
    id: mac

    property string uuid: ""          // active wifi connection
    property string mode: ""          // off | stable | random | "" (unknown)
    property string address: ""       // MAC currently in use
    property bool randomized: false   // differs from the hardware (phy) MAC
    property bool busy: false

    function refresh() { if (!readProc.running) readProc.running = true }

    function setMode(m) {
        if (busy || uuid === "" || m === mode) return
        busy = true
        mode = m
        const v = m === "off" ? "permanent" : m
        setProc.command = ["sh", "-c",
            'nmcli connection modify uuid "$1" 802-11-wireless.cloned-mac-address "$2" && nmcli -w 30 connection up uuid "$1"',
            "sh", uuid, v]
        setProc.running = true
    }

    // uuid|iface|cloned-mac-address|current MAC|hardware MAC
    Process {
        id: readProc
        command: ["sh", "-c",
            'set -- $(nmcli -t -f UUID,TYPE,DEVICE connection show --active | awk -F: \'$2=="802-11-wireless"{print $1, $3; exit}\'); ' +
            '[ -n "$1" ] || exit 0; ' +
            'printf "%s|%s|%s|%s|%s" "$1" "$2" "$(nmcli -g 802-11-wireless.cloned-mac-address connection show uuid "$1")" ' +
            '"$(cat /sys/class/net/$2/address)" "$(cat /sys/class/net/$2/phy80211/macaddress)"']
        stdout: StdioCollector {
            onStreamFinished: {
                const f = (this.text || "").trim().split("|")
                if (f.length < 5) { mac.uuid = ""; mac.mode = ""; mac.address = ""; return }
                mac.uuid = f[0]
                mac.mode = f[2] === "stable" || f[2] === "random" ? f[2] : "off"
                mac.address = f[3].toUpperCase()
                mac.randomized = f[4] !== "" && f[4].toUpperCase() !== mac.address
            }
        }
    }

    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }
        onExited: (code) => {
            mac.busy = false
            mac.refresh()
            if (code !== 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", I18n.tr("Private MAC address"),
                    setErr.text.trim() || "exit code " + code])
        }
    }

    // Re-read when the WiFi network changes.
    Connections {
        target: Net
        function onSsidChanged() { mac.refresh() }
    }
    Component.onCompleted: refresh()
}
