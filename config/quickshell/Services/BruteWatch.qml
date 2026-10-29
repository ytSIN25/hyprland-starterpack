pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Ataques de fuerza bruta: muchas contraseñas o conexiones seguidas desde el
// mismo sitio contra el mismo servicio. Dos fuentes:
//   auth: contraseñas fallidas (AuthWatch): sshd "Failed password for … from IP",
//         y pam de sudo, su, pantalla de bloqueo, login, polkit…
//   conn: conexiones nuevas al 22 (SSH) o al 5900 (VNC) que deja pasar el
//         firewall (FwActivity, "qs-fw-in"). Pilla también lo que no llega a
//         pedir contraseña: SSH con sshd apagado, o VNC (wayvnc no deja log).
// Al pasar el umbral, si viene de otra máquina, la bloquea en el firewall
// blockMin minutos (FwBlock) sin preguntar, y emite attack() (FwActivity →
// Activity, Island → aviso),
// como mucho uno cada 5 min por servicio y origen; los intentos siguientes
// llegan por attempt() para que la cuenta de Activity siga subiendo.
Singleton {
    id: root

    // b: { key, service, ip, users, count, kind, t, backfill }
    signal attack(var b)
    signal attempt(var b)

    readonly property var limits: ({
        auth: { n: 5, ms: 120000 },     // 5 contraseñas mal en 2 min
        // SSH: faillock cierra tras 5 (install-ssh-faillock.sh); bloquear la IP
        // solo si sigue probando después, para no echarte por equivocarte
        sshAuth: { n: 8, ms: 120000 },
        conn: { n: 12, ms: 60000 }      // 12 conexiones en 1 min
    })
    readonly property int realertMs: 300000
    readonly property int blockMin: 60

    property var _hits: ({})            // key|kind → [ms]
    property var _alertedAt: ({})       // key → ms
    property var _users: ({})           // key → [usuarios probados]

    function key(service, ip) { return service + "|" + (ip || "local") }
    // Esa IP está atacando ahora (la isla no pregunta "¿Allow SSH?" a un atacante)
    function isAttacking(ip) {
        const now = Date.now()
        for (const k in _alertedAt)
            if (k.endsWith("|" + ip) && now - _alertedAt[k] < realertMs) return true
        return false
    }

    readonly property real _start: Date.now()
    // t: hora del intento (ms); al rellenar desde el journal es la del log
    function hit(service, ip, user, kind, t) {
        const now = t || Date.now(), k = key(service, ip)
        const lim = kind === "auth" && service === "SSH" ? limits.sshAuth : limits[kind]
        const h = Object.assign({}, _hits)
        h[k + "|" + kind] = (h[k + "|" + kind] || []).filter(t => now - t < lim.ms).concat([now])
        _hits = h
        if (user) {
            const u = Object.assign({}, _users)
            const list = u[k] || []
            if (list.indexOf(user) < 0) u[k] = list.concat([user]).slice(-8)
            _users = u
        }
        const b = { key: k, service: service, ip: ip || "", kind: kind, t: now, backfill: now < _start,
                    users: _users[k] || [], count: h[k + "|" + kind].length }
        if (now - (_alertedAt[k] || 0) < realertMs) {
            attempt(b)
            return
        }
        if (b.count < lim.n) return
        const a = Object.assign({}, _alertedAt)
        a[k] = now
        _alertedAt = a
        if (b.ip && !b.backfill) {
            FwBlock.block(b.ip, blockMin)
            b.blocked = true
        }
        attack(b)
    }

    // "SSH", "VNC", "sudo", "Lock screen"…
    function serviceName(port) { return port === "22" ? "SSH" : port === "5900" ? "VNC" : "TCP " + port }

    // Ataques SSH de las últimas 24 h, una vez al arrancar (sin avisar)
    Process {
        running: true
        command: ["journalctl", "-q", "--no-pager", "-o", "short-unix", "--since", "-24h",
                  "-u", "sshd", "-g", "^Failed \\S+ for "]
        stdout: SplitParser {
            onRead: (line) => {
                const m = line.match(/^(\d+)\.(\d{3})\S*\s.*?: Failed \S+ for (?:invalid user )?(\S*) from (\S+) port/)
                if (m) root.hit("SSH", m[4], m[3], "auth", Number(m[1]) * 1000 + Number(m[2]))
            }
        }
    }

    Connections {
        target: AuthWatch
        function onSshFailed(user, ip, method) { root.hit("SSH", ip, user, "auth") }
        function onFailed(service, user, where, count) {
            // sshd ya cuenta por sus propias líneas ("Failed password …")
            if (service === "sshd") return
            const ip = (where.match(/(\S+)$/) || [])[1] || ""
            const remote = where.indexOf(I18n.tr("from %1").arg("")) === 0
            root.hit(AuthWatch.label(service), remote ? ip : "", user, "auth")
        }
    }
}
