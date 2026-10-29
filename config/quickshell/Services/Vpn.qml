pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// VPN (TryHackMe / OpenVPN): envuelve el unit systemd "openvpn-client@thm".
// Requiere que /etc/openvpn/client/thm.conf exista y que el usuario tenga
// permiso NOPASSWD (sudoers.d) para start/stop/is-active de ese unit.
Singleton {
    id: vpn

    property bool connected: false
    // true mientras se está conectando o desconectando (evita doble-click
    // y deja que el icono muestre un estado "en progreso" si se quiere).
    property bool busy: false

    function toggle() {
        if (busy) return
        busy = true
        toggleProc.command = connected
            // Ruta completa y -n: el root lock (qs-remote-guard) solo deja pasar
            // estos comandos tal cual, también con alguien conectado por SSH/VNC
            ? ["sudo", "-n", "/usr/bin/systemctl", "stop", "openvpn-client@thm"]
            : ["sudo", "-n", "/usr/bin/systemctl", "start", "openvpn-client@thm"]
        toggleProc.running = true
    }

    Process {
        id: toggleProc
        onExited: {
            vpn.busy = false
            // systemd tarda un instante en asentar el estado (sobre todo al
            // levantar la interfaz tun0); pequeño margen antes de releer.
            recheckDelay.restart()
        }
    }

    Timer {
        id: recheckDelay
        interval: 400
        onTriggered: statusProc.running = true
    }

    Process {
        id: statusProc
        command: ["systemctl", "is-active", "openvpn-client@thm"]
        stdout: StdioCollector {
            onStreamFinished: vpn.connected = this.text.trim() === "active"
        }
    }

    // Sondeo periódico por si el túnel cae solo (red inestable, servidor
    // remoto, etc.) y para reflejar el estado real al arrancar el shell.
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }
}
