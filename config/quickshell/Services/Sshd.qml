pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Servidor SSH local (sshd), mismo patrón que Vpn.qml. Solo start/stop --
// no toca "enable"/"disable", así que no cambia el arranque automático;
// eso se deja aparte (systemctl enable sshd) si algún día se quiere fijo.
// Sin sudo: systemctl pide permiso a polkit, y la regla
// /etc/polkit-1/rules.d/50-sshd-toggle.rules permite start/stop de
// sshd.service a este usuario sin contraseña. Si falla, se avisa.
Singleton {
    id: sshd

    property bool running: false
    property bool busy: false
    // IP local (LAN), no pública: es lo que de verdad se usa para
    // conectarse por SSH desde otro equipo de la misma red.
    property string localIp: ""

    function toggle() {
        if (busy) return
        busy = true
        // --no-ask-password: sin la regla de polkit falla al momento en vez
        // de quedarse esperando una contraseña que nadie puede escribir.
        toggleProc.command = ["systemctl", "--no-ask-password", running ? "stop" : "start", "sshd"]
        toggleProc.running = true
    }

    // Encender (no apagar): lo usa la pregunta de SSH de la isla.
    function start() {
        if (!running) toggle()
    }

    function refreshLocalIp() {
        if (!ipProc.running) ipProc.running = true
    }

    Process {
        id: toggleProc
        stderr: StdioCollector { id: toggleErr }
        onExited: (code) => {
            sshd.busy = false
            recheckDelay.restart()
            if (code !== 0)
                Quickshell.execDetached(["notify-send", "-a", "Quickshell", "SSH server",
                    "Could not toggle sshd: " + (toggleErr.text.trim() || "exit code " + code)])
        }
    }

    Timer {
        id: recheckDelay
        interval: 400
        onTriggered: {
            statusProc.running = true
            sshd.refreshLocalIp()
        }
    }

    Process {
        id: statusProc
        command: ["systemctl", "is-active", "sshd"]
        stdout: StdioCollector {
            onStreamFinished: sshd.running = this.text.trim() === "active"
        }
    }

    // `hostname -I` puede listar varias interfaces separadas por espacio
    // (ethernet, wifi, tun0 de la VPN...); se toma la primera, que suele
    // ser la interfaz "principal" de la máquina.
    Process {
        id: ipProc
        command: ["sh", "-c", "hostname -I | awk '{print $1}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                if (/^[0-9a-fA-F:.]+$/.test(t)) sshd.localIp = t
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }
}
