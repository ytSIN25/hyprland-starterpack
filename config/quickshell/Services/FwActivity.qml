pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Actividad de red de otros hacia este PC (panel del firewall → Activity, y
// avisos en la isla). Sale del log del kernel que escribe el firewall del
// shell (scripts/qs-firewall.nft):
//   qs-fw-in:   conexión nueva o ping que entra (SSH, ZeroTier/Tailscale…)
//   qs-fw-drop: paquete bloqueado
// más los escaneos de puertos de ScanWatch y los sudo/su que el root lock
// rechazó (AuthWatch en directo; journal de qs-remote-guard al arrancar).
// Al arrancar se rellena con las últimas 24 h del journal (sin avisar); lo que
// llega después avisa en la isla, una vez cada 10 min por tipo e IP.
Singleton {
    id: root

    // Evento nuevo en directo (no del relleno inicial) → aviso en la isla
    signal activity(var e)
    // Cada intento de SSH en directo, sin el límite de 10 min (la isla
    // pregunta si encender sshd para esa IP)
    signal sshKnock(string ip, string who)
    // Cada paquete de ping en directo ("qs-fw-ping:", máx. 2/s por IP): la
    // isla mantiene el aviso de ping mientras sigan llegando
    signal pingSeen(string ip)

    // [{ id, t (ms), kind, ip, who, where, iface, proto, port, service, n }], el más nuevo primero
    property var events: []
    readonly property int maxEvents: 150
    readonly property real _start: Date.now()
    property var _alerted: ({})             // "kind|ip" → ms del último aviso
    property real _lastLine: 0              // si journalctl se reinicia, no repetir líneas

    // Nombres para IPs conocidas (como en qs-netwatch)
    readonly property var known: ({ "10.18.178.224": "MacBook (ZeroTier)" })
    readonly property var services: ({
        "21": "FTP", "22": "SSH", "23": "Telnet", "25": "SMTP", "53": "DNS", "80": "HTTP",
        "110": "POP3", "135": "RPC", "137": "NetBIOS", "138": "NetBIOS", "139": "NetBIOS",
        "143": "IMAP", "443": "HTTPS", "445": "SMB", "1433": "MSSQL", "1900": "SSDP",
        "3306": "MySQL", "3389": "RDP",
        "5432": "Postgres", "5900": "VNC", "6379": "Redis", "8080": "HTTP",
        "8443": "HTTPS", "24800": "Deskflow"
    })
    readonly property var kinds: ({
        ping:    { label: "Ping",       icon: "\u{f0430}", color: Theme.accent },
        ssh:     { label: "SSH",        icon: "\u{f018d}", color: Theme.yellow },
        rootlock: { label: "Root lock", icon: "\u{f033e}", color: Theme.red },
        brute:   { label: "Brute force", icon: "\u{f08ee}", color: Theme.red },
        login:    { label: "SSH login", icon: "\u{f0342}", color: Theme.green },
        logout:   { label: "SSH logout", icon: "\u{f0343}", color: Theme.fgMuted },
        connect: { label: "Connection", icon: "\u{f0318}", color: Theme.green },
        blocked: { label: "Blocked",    icon: "\u{f0ecc}", color: Theme.fgDim },
        banned:  { label: "Banned IP",  icon: "\u{f0ecc}", color: Theme.red },
        scan:    { label: "Port scan",  icon: "\u{f0437}", color: Theme.red }
    })

    function where(ip) {
        if (ip.startsWith("10.18.178.")) return "ZeroTier"
        if (ip.startsWith("100.") || ip.startsWith("fd7a:115c")) return "Tailscale"
        if (ip.startsWith("192.168.56.")) return "VirtualBox"
        if (/^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.|fe80:|fd|fc)/.test(ip)) return "Home network"
        return "Internet"
    }

    // false mientras /etc/qs-firewall.nft sea la versión sin "qs-fw-in"
    // (falta instalar scripts/qs-firewall.nft): solo se ven los bloqueos.
    property bool rulesReady: true
    Process {
        running: true
        command: ["grep", "-q", "qs-fw-in", "/etc/qs-firewall.nft"]
        onExited: (code) => root.rulesReady = code === 0
    }

    // Filtro del panel: los logout van con los login
    function group(kind) { return kind === "logout" ? "login" : kind === "banned" ? "blocked" : kind }

    function clear() {
        events = []
        Settings.fwActivityClearedAt = Date.now()
    }

    function _parse(line) {
        const m = line.match(/^(\d+)\.(\d+)\s.*?qs-fw-(in|drop|ping|banned):\s(.*)$/)
        if (!m) return
        const t = Number(m[1]) * 1000 + Math.floor(Number(m[2].slice(0, 3).padEnd(3, "0")))
        if (m[3] === "ping") {
            const src = (m[4].match(/\bSRC=(\S+)/) || [])[1]
            if (src && t >= _start) pingSeen(src)
            return
        }
        if (t <= _lastLine) return
        _lastLine = t
        const kv = {}
        for (const p of m[4].split(/\s+/)) {
            const i = p.indexOf("=")
            if (i > 0) kv[p.slice(0, i)] = p.slice(i + 1)
        }
        const ip = kv.SRC || "", iface = kv.IN || "", proto = kv.PROTO || "", port = kv.DPT || ""
        // Ruido que no es nadie conectando: Docker, IGMP, DHCP, 0.0.0.0
        if (!ip || ip === "0.0.0.0" || /^(docker|br-|veth)/.test(iface)) return
        if (proto === "2" || (kv.SPT === "67" && port === "68")) return

        // Muchas conexiones seguidas al SSH/VNC: posible fuerza bruta
        if (m[3] === "in" && proto === "TCP" && (port === "22" || port === "5900") && t >= _start)
            BruteWatch.hit(BruteWatch.serviceName(port), ip, "", "conn")

        // IP bloqueada desde la barra (fuerza bruta, escaneo) que sigue probando
        if (m[3] === "banned") {
            _add({ t: t, kind: "banned", ip: ip, iface: iface, proto: proto, port: port })
            return
        }

        // Mientras esa IP escanea, sus paquetes van al informe del escaneo
        if (proto !== "ICMP" && proto !== "ICMPv6" && ScanWatch.isScanning(ip)) return

        let kind
        if (m[3] === "drop") kind = "blocked"
        else if (proto === "ICMP" || proto === "ICMPv6") kind = "ping"
        else if (port === "22") kind = "ssh"
        else kind = "connect"
        _add({ t: t, kind: kind, ip: ip, iface: iface, proto: proto, port: port })
    }

    function _add(e) {
        if (e.t <= Settings.fwActivityClearedAt || e.t < Date.now() - 86400000) return
        // Root lock: ip = quién estaba conectado ("" si no se sabe, p. ej. al
        // rellenar desde el journal), port = sudo/su, note = "sudo refused · playera"
        e.where = e.kind === "rootlock" ? e.note
                : e.kind === "brute" ? (e.ip ? where(e.ip) + " · " : "") + e.note
                : e.kind === "login" ? where(e.ip) + " · " + e.note
                : e.kind === "logout" ? where(e.ip) + " · " + e.note : where(e.ip)
        e.who = known[e.ip] || e.ip || (e.kind === "brute" ? I18n.tr("This PC") : I18n.tr("Remote session"))
        if (e.ip) { _named(e); HostNames.lookup(e.ip) }
        e.service = e.kind === "ping" ? (e.proto === "ICMPv6" ? "ICMPv6" : "ICMP")
                  : e.kind === "scan" || e.kind === "rootlock" || e.kind === "brute" || e.kind === "login" || e.kind === "logout" ? e.proto
                  : (services[e.port] || "") + (services[e.port] ? "" : (e.proto + " " + e.port).trim())
        e.n = e.n || 1
        // Lo mismo (tipo, IP, puerto) en menos de 2 min: se suma al anterior
        const key = e.kind + "|" + e.ip + "|" + e.port
        const i = events.findIndex(x => x.key === key && e.t - x.t < 120000)
        let list = events.slice()
        if (i >= 0) {
            const prev = list.splice(i, 1)[0]
            e.n = prev.n + e.n
            e.first = prev.first
        } else {
            e.first = e.t
        }
        e.key = key
        e.id = key + "|" + e.first
        list.unshift(e)
        // Llegan de dos journals (kernel y root lock): por hora, el más nuevo primero
        list.sort((x, y) => y.t - x.t)
        if (list.length > maxEvents) list = list.slice(0, maxEvents)
        events = list

        // Avisos solo en directo. Se esperan 1,5 s: si para entonces esa IP
        // está escaneando, el aviso lo da el informe del escaneo (y un nmap
        // que toca el 22 no abre la pregunta de SSH)
        // Root lock y logins SSH ya avisan en la isla por su cuenta (AuthWatch)
        if (e.t < _start || e.kind === "brute" || e.kind === "rootlock" || e.kind === "login" || e.kind === "logout") return
        if (e.kind === "scan") { _alert(e); return }
        root._later = _later.concat([{ at: Date.now(), e: e }])
        laterTimer.start()
    }

    // Con nombre (HostNames): "Samsung" y la IP pasa a la segunda línea
    function _named(e) {
        const n = known[e.ip] ? "" : HostNames.label(e.ip)
        if (!n || e.who === n) return
        e.who = n
        e.where = e.where + " · " + e.ip
    }
    Connections {
        target: HostNames
        function onResolved(ip) {
            if (!HostNames.label(ip) || !root.events.some(x => x.ip === ip)) return
            root.events = root.events.map(x => {
                if (x.ip !== ip) return x
                const y = Object.assign({}, x)
                root._named(y)
                return y
            })
        }
    }

    function _alert(e) {
        if (e.kind === "ssh") sshKnock(e.ip, e.who)
        // Por tipo e IP, como mucho uno cada: ping/SSH 15 s (cada `ping` o
        // `ssh` nuevo avisa), conexión 1 min, bloqueado 10 min
        const ak = e.kind + "|" + e.ip
        const gap = e.kind === "ping" ? 3000 : e.kind === "ssh" || e.kind === "banned" ? 15000
                  : e.kind === "connect" ? 60000 : 600000
        if (Date.now() - (_alerted[ak] || 0) < gap) return
        const a = Object.assign({}, _alerted)
        a[ak] = Date.now()
        _alerted = a
        activity(e)
    }
    property var _later: []
    Timer {
        id: laterTimer
        interval: 1500
        onTriggered: {
            const now = Date.now(), keep = []
            for (const x of root._later) {
                if (now - x.at < 1400) keep.push(x)
                else if (x.e.kind === "ping" || !ScanWatch.isScanning(x.e.ip)) root._alert(x.e)
            }
            root._later = keep
            if (keep.length > 0) laterTimer.restart()
        }
    }

    Connections {
        target: ScanWatch
        function onScan(r) {
            // Lo que se apuntó suelto antes de saber que era un escaneo, fuera
            root.events = root.events.filter(x => !(x.ip === r.src && x.t >= r.first - 2000
                                                    && (x.kind === "blocked" || x.kind === "connect" || x.kind === "ssh")))
            root._add({ t: r.last, kind: "scan", ip: r.src, iface: "", proto: r.type + " · " + r.probed + " ports", port: "", scan: r })
        }
    }

    // "22 SSH, 5900 VNC" (como mucho `max`, y "+N" si hay más)
    function portList(list, max) {
        const out = list.slice(0, max).map(p => p.port + (services[p.port] ? " " + services[p.port] : "")
                                               + (p.proto === "UDP" ? "/udp" : ""))
        if (list.length > max) out.push("+" + (list.length - max))
        return out.join(", ")
    }

    // ── Fuerza bruta (BruteWatch) ───────────────────────────────────────────
    // proto/port = servicio, note = "12 wrong passwords · tried root, admin"
    function _bruteNote(b) {
        const what = b.kind === "auth" ? I18n.tr("wrong passwords") : I18n.tr("connections in a row")
        return what + (b.users.length > 0 ? " · " + I18n.tr("tried %1").arg(b.users.join(", ")) : "")
    }
    Connections {
        target: BruteWatch
        function onAttack(b) {
            root._add({ t: b.t, kind: "brute", ip: b.ip, iface: "", proto: b.service, port: b.service,
                        n: b.count, note: (b.blocked ? I18n.tr("blocked %1 min").arg(BruteWatch.blockMin) + " · " : "")
                                         + root._bruteNote(b) })
        }
        function onAttempt(b) {
            root._add({ t: b.t, kind: "brute", ip: b.ip, iface: "", proto: b.service, port: b.service,
                        n: 1, note: root._bruteNote(b) })
        }
    }

    // ── Root lock ───────────────────────────────────────────────────────────
    function _rootlock(t, service, user, who) {
        _add({ t: t, kind: "rootlock", ip: who, iface: "", proto: service, port: service,
               note: I18n.tr("%1 refused · %2").arg(service).arg(user) })
    }
    // Login SSH: proto = cómo (password/publickey), note = usuario
    function _login(t, user, ip, method) {
        _add({ t: t, kind: "login", ip: ip, iface: "", proto: method, port: user, note: user })
    }
    // Salida de SSH: proto = "exit", note = usuario
    function _logout(t, user, ip) {
        _add({ t: t, kind: "logout", ip: ip, iface: "", proto: I18n.tr("exit"), port: user, note: user })
    }
    Connections {
        target: AuthWatch
        function onRootLocked(service, user, who) {
            root._rootlock(Date.now(), service, user, (who || "").split(", ")[0])
        }
        function onSshLogin(user, ip, method) { root._login(Date.now(), user, ip, method) }
        function onSshLogout(user, ip) { root._logout(Date.now(), user, ip) }
    }
    // Logins SSH de las últimas 24 h, una vez al arrancar
    Process {
        running: true
        command: ["journalctl", "-q", "--no-pager", "-o", "short-unix", "--since", "-24h",
                  "-g", "^(Accepted \\S+ for|Disconnected from user) \\S+ "]
        stdout: SplitParser {
            onRead: (line) => {
                let m = line.match(/^(\d+)\.\d+\s.*?: Accepted (\S+) for (\S+) from (\S+) port/)
                if (m) root._login(Number(m[1]) * 1000, m[3], m[4], m[2])
                else if ((m = line.match(/^(\d+)\.\d+\s.*?: Disconnected from user (\S+) (\S+) port/)))
                    root._logout(Number(m[1]) * 1000, m[2], m[3])
            }
        }
    }
    // Las últimas 24 h, una vez al arrancar (el log no dice quién estaba conectado)
    Process {
        running: true
        command: ["journalctl", "-q", "--no-pager", "-o", "short-unix", "--since", "-24h",
                  "-t", "qs-remote-guard", "-g", "^refused "]
        stdout: SplitParser {
            onRead: (line) => {
                const m = line.match(/^(\d+)\.\d+\s.*refused (\S+) \(\w+\) for (\S+):/)
                if (m) root._rootlock(Number(m[1]) * 1000, m[2], m[3], "")
            }
        }
    }

    Process {
        id: kmsg
        running: true
        command: ["journalctl", "-k", "-f", "-n", "1000", "-q", "-o", "short-unix",
                  "--no-pager", "-g", "qs-fw-(in|drop|ping|banned):"]
        stdout: SplitParser { onRead: (line) => root._parse(line) }
        onExited: restart.start()
    }
    Timer {
        id: restart
        interval: 5000
        onTriggered: kmsg.running = true
    }
}
