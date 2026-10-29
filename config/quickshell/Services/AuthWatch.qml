pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Contraseñas fallidas (sudo, pantalla de bloqueo, login, su, polkit, ssh…):
// sigue el journal del sistema (el grupo wheel puede leerlo) y emite
// failed() por cada intento. La isla (Services/Island.qml) lo muestra.
// Fallos en la pantalla de bloqueo se acumulan en lockFails para avisar al
// desbloquear ("2 failed unlock attempts while you were away").
Singleton {
    id: root

    signal failed(string service, string user, string where, int count)
    signal locked(string service, string user)
    signal awaySummary(int count, var photos)
    // SSH con un usuario que no existe aquí (p. ej. el nombre del otro equipo)
    signal invalidUser(string user, string ip)
    // Root lock (qs-remote-guard): sudo/su rechazado porque hay alguien
    // conectado por SSH/VNC. who = quién está conectado ("ip:puerto, …")
    signal rootLocked(string service, string user, string who)
    // Login SSH correcto (sshd: "Accepted password for playera from 1.2.3.4 port 5")
    signal sshLogin(string user, string ip, string method)
    // Salida de SSH (sshd: "Disconnected from user playera 1.2.3.4 port 5")
    signal sshLogout(string user, string ip)
    // Contraseña/clave SSH rechazada (sshd: "Failed password for [invalid user] x from 1.2.3.4 port 5")
    signal sshFailed(string user, string ip, string method)

    property int lockFails: 0
    // service → { n, t } para contar repeticiones seguidas (60 s)
    property var _recent: ({})

    function label(service) {
        return ({
            "sudo": "sudo", "su": "su", "hyprlock": "Lock screen", "login": "TTY login",
            "sddm": "Login screen", "greetd": "Login screen", "gdm-password": "Login screen",
            "sshd": "SSH", "polkit-1": "Admin prompt", "systemd-user": "Session"
        })[service] ?? service
    }

    function _line(msg) {
        let m
        if ((m = msg.match(/^Accepted (\S+) for (\S+) from (\S+) port \d+/))) {
            root.sshLogin(m[2], m[3], m[1])
        } else if ((m = msg.match(/^Failed (\S+) for (?:invalid user )?(\S*) from (\S+) port \d+/))) {
            root.sshFailed(m[2], m[3], m[1])
        } else if ((m = msg.match(/^Disconnected from user (\S+) (\S+) port \d+/))) {
            root.sshLogout(m[1], m[2])
        } else if ((m = msg.match(/^Invalid user (\S*) from (\S+)/))) {
            root.invalidUser(m[1], m[2])
        } else if ((m = msg.match(/^refused (\S+) \(\w+\) for (\S+): remote connection active/))) {
            // Un mismo intento puede dar auth + account: uno cada 3 s
            if (Date.now() - root._lockAt < 3000) return
            root._lockAt = Date.now()
            peersProc.service = m[1]
            peersProc.user = m[2]
            if (!peersProc.running) peersProc.running = true
        } else if ((m = msg.match(/pam_unix\(([^:]+):auth\): authentication failure;(.*)$/))) {
            const service = m[1], rest = m[2]
            const user = (rest.match(/\buser=(\S+)/) || [])[1] || "?"
            // Usuario inexistente por SSH: ya avisó invalidUser
            if (service === "sshd" && user === "?") return
            const rhost = (rest.match(/\brhost=(\S+)/) || [])[1] || ""
            const tty = ((rest.match(/\btty=(\S+)/) || [])[1] || "").replace(/^\/dev\//, "")
            const now = Date.now()
            const prev = _recent[service]
            const n = prev && now - prev.t < 60000 ? prev.n + 1 : 1
            const r = Object.assign({}, _recent)
            r[service] = { n: n, t: now }
            root._recent = r
            if (service === "hyprlock") {
                root.lockFails++
                // Foto con la webcam al 3.º, 6.º y 9.º intento fallido.
                if (root.lockFails % 3 === 0 && root.lockFails <= 9 && !photo.running)
                    photo.running = true
            }
            root.failed(service, user, rhost !== "" ? I18n.tr("from %1").arg(rhost) : tty, n)
        } else if ((m = msg.match(/pam_faillock\(([^:]+):auth\): Consecutive login failures for user (\S+)/))) {
            root.locked(m[1], m[2])
        }
    }

    // -g filtra en journalctl: solo llegan las líneas que interesan.
    Process {
        id: journal
        running: true
        command: ["journalctl", "-f", "-n0", "-q", "-o", "cat",
                  "-g", "pam_unix\\([^:]+:auth\\): authentication failure|pam_faillock\\(.*Consecutive login failures|^Invalid user \\S* from |^refused \\S+ \\(\\w+\\) for \\S+: remote connection active|^Accepted \\S+ for \\S+ from |^Disconnected from user \\S+ |^Failed \\S+ for "]
        stdout: SplitParser { onRead: (line) => root._line(line) }
        onExited: restart.start()
    }
    Timer {
        id: restart
        interval: 5000
        onTriggered: journal.running = true
    }

    // Quién mantiene el root lock (las mismas comprobaciones que el guard)
    property real _lockAt: 0
    Process {
        id: peersProc
        property string service: ""
        property string user: ""
        command: ["/usr/local/sbin/qs-remote-guard", "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const who = (this.text || "").trim().split("\n").filter(x => x && !x.startsWith("ssh-session"))
                    .map(x => x.replace(/:\d+$/, "").replace(/^\[(.*)\]$/, "$1"))
                root.rootLocked(peersProc.service, peersProc.user, [...new Set(who)].join(", "))
            }
        }
    }

    // Fotos del "intruso" de este bloqueo (scripts/intruder-photo.sh).
    property var photos: []
    Process {
        id: photo
        command: ["bash", decodeURIComponent(Qt.resolvedUrl("../scripts/intruder-photo.sh")
                                             .toString().replace(/^file:\/\//, ""))]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = (this.text || "").trim()
                if (p !== "") root.photos = root.photos.concat([p])
            }
        }
    }

    // Al cerrarse hyprlock (desbloqueo) se resumen los fallos mientras estaba.
    property bool _lockUp: false
    readonly property bool lockActive: _lockUp
    Process {
        id: lockProbe
        command: ["pgrep", "-x", "hyprlock"]
        onExited: (code) => {
            const up = code === 0
            if (root._lockUp && !up && root.lockFails > 0) {
                root.awaySummary(root.lockFails, root.photos)
                root.lockFails = 0
            }
            if (!root._lockUp && up) { root.lockFails = 0; root.photos = [] }
            root._lockUp = up
        }
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: if (!lockProbe.running) lockProbe.running = true
    }
}
