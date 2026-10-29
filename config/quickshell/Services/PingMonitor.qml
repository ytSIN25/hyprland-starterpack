pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Monitor de una IP a mano (p. ej. la box de una sala de TryHackMe): el
// usuario la escribe una vez desde el modal, y esto le hace ping cada
// pocos segundos para saber si sigue viva. No se persiste entre reinicios
// del shell a propósito -- cada sala nueva es una IP distinta, así que
// guardarla "para siempre" no aporta gran cosa y complica el archivo de
// ajustes sin necesidad.
Singleton {
    id: pm

    property string targetIp: ""
    property bool online: false
    // false hasta el primer resultado real de ping -- así el botón puede
    // distinguir "aún no lo sé" de "confirmado offline" en vez de arrancar
    // en rojo antes de haber comprobado nada.
    property bool hasResult: false
    property bool open: false

    function openPrompt() { open = true }
    function closePrompt() { open = false }

    function setIp(ip) {
        const t = ip.trim()
        if (t === "") return
        targetIp = t
        hasResult = false
        open = false
        refresh()
    }

    function clear() {
        targetIp = ""
        hasResult = false
        online = false
    }

    function refresh() {
        if (targetIp === "" || pingProc.running || tcpProc.running) return
        pingProc.command = ["ping", "-c", "1", "-W", "1", targetIp]
        pingProc.running = true
    }

    Process {
        id: pingProc
        onExited: (code, status) => {
            if (code === 0) {
                pm.hasResult = true
                pm.online = true
            } else {
                // ICMP puede estar bloqueado (típico en Windows con el
                // Firewall por defecto) aunque la máquina esté viva, así
                // que antes de darla por offline se prueba con un connect
                // TCP a puertos habituales (RDP/SMB/WinRM/RPC + web/SSH).
                tcpProc.command = ["bash", "-c",
                    "for p in 3389 445 5985 135 80 443 22 8080; do " +
                    "timeout 1 bash -c \"echo >/dev/tcp/" + pm.targetIp + "/$p\" 2>/dev/null && exit 0; " +
                    "done; exit 1"]
                tcpProc.running = true
            }
        }
    }

    Process {
        id: tcpProc
        onExited: (code, status) => {
            pm.hasResult = true
            pm.online = (code === 0)
        }
    }

    Timer {
        interval: 4000
        running: pm.targetIp !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: pm.refresh()
    }
}
