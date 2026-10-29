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
        "8443": "HTTPS", "24800": "Deskflow", "3283": "Apple Remote Desktop",
        "5800": "VNC (web)", "5901": "VNC", "5902": "VNC", "5903": "VNC", "5938": "TeamViewer"
    })
    readonly property var kinds: ({
        ping:    { label: "Ping",       icon: "\u{f0430}", color: Theme.accent },
        ssh:     { label: "SSH",        icon: "\u{f018d}", color: Theme.yellow },
        rootlock: { label: "Root lock", icon: "\u{f033e}", color: Theme.red },
        rootkill: { label: "Root session ended", icon: "\u{f033e}", color: Theme.orange },
        brute:   { label: "Brute force", icon: "\u{f08ee}", color: Theme.red },
        login:    { label: "SSH login", icon: "\u{f0342}", color: Theme.green },
        logout:   { label: "SSH logout", icon: "\u{f0343}", color: Theme.fgMuted },
        connect: { label: "Connection", icon: "\u{f0318}", color: Theme.green },
        blocked: { label: "Blocked",    icon: "\u{f0ecc}", color: Theme.fgDim },
        banned:  { label: "Banned IP",  icon: "\u{f0ecc}", color: Theme.red },
        scan:    { label: "Port scan",  icon: "\u{f0437}", color: Theme.red },
        nmap:    { label: "Nmap scan",  icon: "\u{f0437}", color: Theme.red }
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

    // ── Gravedad y titular de cada evento (consola del panel) ──────────────
    // Puertos que nadie de fuera debería tocar: intentarlo ya es sospechoso
    readonly property var riskyPorts: ["21", "23", "25", "135", "139", "445", "1433", "3306",
                                       "3389", "5432", "5900", "6379"]
    // Acceso remoto / control del equipo: siempre se avisa y es "high"
    readonly property var remotePorts: ["21", "22", "23", "445", "3283", "3389", "5800",
                                        "5900", "5901", "5902", "5903", "5938"]
    // ¿Es un intento de acceso remoto (VNC, RDP, Telnet, FTP, SMB…)? Esos
    // avisan siempre, aunque la IP esté mandando mucho tráfico ("escaneando").
    function _remoteAccess(e) {
        return (e.kind === "connect" || e.kind === "blocked" || e.kind === "banned")
               && remotePorts.indexOf(e.port) !== -1
    }
    readonly property var levels: ({
        critical: { label: "CRIT", rank: 4, color: Theme.red },
        high:     { label: "HIGH", rank: 3, color: Theme.orange },
        medium:   { label: "MED",  rank: 2, color: Theme.yellow },
        low:      { label: "LOW",  rank: 1, color: Theme.cyan },
        info:     { label: "INFO", rank: 0, color: Theme.fgMuted }
    })
    function severity(e) {
        const internet = where(e.ip || "") === "Internet"
        switch (e.kind) {
        case "brute": case "rootlock": return "critical"
        case "rootkill": return "high"
        case "scan": case "nmap": return "high"
        case "banned": return "medium"
        case "login": return known[e.ip] ? "info" : "high"
        case "logout": return "info"
        case "ssh": return "high"
        case "connect": return internet || remotePorts.indexOf(e.port) !== -1 ? "high" : "low"
        case "blocked": return riskyPorts.indexOf(e.port) !== -1 ? "medium" : "low"
        default: return "low"
        }
    }
    function headline(e) {
        switch (e.kind) {
        case "ping": return I18n.tr("ICMP echo request (ping)")
        case "ssh": return I18n.tr("SSH connection attempt")
        case "connect": return remotePorts.indexOf(e.port) !== -1 ? I18n.tr("%1 connection detected").arg(e.service)
                                                                 : I18n.tr("%1 connection accepted").arg(e.service)
        case "blocked": return I18n.tr("%1 attempt blocked").arg(e.service)
        case "banned": return I18n.tr("Banned host still probing") + " · " + I18n.tr("last %1").arg(e.service)
        case "scan": return I18n.tr("Nmap scan detected") + (e.scan && e.scan.stealth ? " " + I18n.tr("(stealth)") : "") + " · " + e.proto
        case "nmap": return I18n.tr("Nmap scan detected (blocked)")
        case "brute": return I18n.tr("Brute-force attack on %1").arg(e.proto)
        case "rootlock": return I18n.tr("Root access refused (%1)").arg(e.proto)
        case "rootkill": return I18n.tr("Root session ended (%1)").arg(e.proto)
        case "login": return I18n.tr("SSH login as %1").arg(e.note) + " · " + e.proto
        case "logout": return I18n.tr("SSH session closed · %1").arg(e.note)
        default: return e.kind
        }
    }

    // ── Nivel de amenaza (0-100) y atacantes de la última hora ─────────────
    property real now: Date.now()
    Timer { interval: 10000; running: true; repeat: true; onTriggered: root.now = Date.now() }
    // Cada evento pesa según su gravedad y se va apagando (vida media ~14 min);
    // lo de IPs baneadas o anterior a un Lockdown ya está contenido y pesa poco
    property real mitigatedAt: 0        // último Lockdown
    property real ackAt: 0              // último "Acknowledge" (oculta la tarjeta)
    function mitigate() { mitigatedAt = Date.now() }
    readonly property int threat: {
        // Lo "low" (tráfico bloqueado de fondo) apenas pesa: 100 bloqueos ≈ 10
        const w = { critical: 35, high: 15, medium: 4, low: 0.1, info: 0 }
        let s = 0
        for (const e of events) {
            const age = Math.max(0, now - e.t)
            if (age > 7200000) continue
            let v = w[severity(e)] * Math.min(e.n, 3) * Math.exp(-age / 1200000)
            if ((e.ip && FwBlock.isBlocked(e.ip)) || e.t <= mitigatedAt) v *= 0.15
            s += v
        }
        return Math.min(100, Math.round(s))
    }
    // Hora del último evento HIGH o CRIT
    readonly property real lastHigh: Math.max(0, ...events.filter(e => levels[severity(e)].rank >= 3).map(e => e.t))
    readonly property bool severe: threat >= 60
    // IPs con algo HIGH o CRIT en la última hora, sin las de confianza:
    // [{ ip, name, n, kinds }], la que más eventos tiene primero
    readonly property var attackers: {
        const m = {}
        for (const e of events) {
            if (!e.ip || known[e.ip] || now - e.t > 3600000 || levels[severity(e)].rank < 3) continue
            const x = m[e.ip] || (m[e.ip] = { ip: e.ip, n: 0, kinds: {} })
            x.n += e.n
            x.kinds[kinds[e.kind] ? kinds[e.kind].label : e.kind] = 1
        }
        return Object.values(m).sort((a, b) => b.n - a.n).map(x => ({
            ip: x.ip, n: x.n, name: HostNames.label(x.ip) || "", kinds: Object.keys(x.kinds).join(", ")
        }))
    }

    // Filtro del panel: los logout van con los login
    // Técnica MITRE ATT&CK de cada evento (como en un SIEM)
    function mitre(e) {
        switch (e.kind) {
        case "scan": return "T1046 Network Service Discovery"
        case "nmap": case "ping": return "T1018 Remote System Discovery"
        case "brute": return "T1110 Brute Force"
        case "ssh": case "login": case "logout": return "T1021.004 Remote Services: SSH"
        case "rootlock": case "rootkill": return "T1548 Abuse Elevation Control"
        case "connect":
            return e.service === "VNC" ? "T1021.005 Remote Services: VNC"
                 : e.service === "RDP" ? "T1021.001 Remote Services: RDP"
                 : e.service === "SMB" ? "T1021.002 Remote Services: SMB" : ""
        default: return ""
        }
    }

    function group(kind) { return kind === "logout" ? "login" : kind === "rootkill" ? "rootlock" : kind === "banned" ? "blocked" : kind === "nmap" ? "scan" : kind }

    // Limpiar vacía solo el feed del panel (los eventos y las cifras de 24 h siguen)
    function clear() { Settings.fwActivityClearedAt = Date.now() }

    function _parse(line) {
        const m = line.match(/^(\d+)\.(\d+)\s.*?qs-fw-(in|drop|ping|banned):\s(.*)$/)
        if (!m) return
        const t = Number(m[1]) * 1000 + Math.floor(Number(m[2].slice(0, 3).padEnd(3, "0")))
        if (t <= _lastLine) return
        _lastLine = t
        if (m[3] === "ping") {
            const src = (m[4].match(/\bSRC=(\S+)/) || [])[1]
            if (!src) return
            if (t >= _start) pingSeen(src)
            const ifc = (m[4].match(/\bIN=(\S+)/) || [])[1] || ""
            _add({ t: t, kind: "ping", ip: src, iface: ifc, proto: m[4].indexOf("PROTO=ICMPv6") !== -1 ? "ICMPv6" : "ICMP", port: "" })
            return
        }
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

        // IP bloqueada desde la barra (fuerza bruta, escaneo) que sigue probando;
        // si está escaneando, sus paquetes van al informe del escaneo
        if (m[3] === "banned" && ScanWatch.isScanning(ip)) return
        if (m[3] === "banned") {
            _add({ t: t, kind: "banned", ip: ip, iface: iface, proto: proto, port: port })
            return
        }

        // Mientras esa IP escanea, sus paquetes van al informe del escaneo…
        // salvo el acceso remoto (VNC, RDP, Telnet, FTP, SMB): eso SIEMPRE se
        // registra y avisa, aunque el equipo mande mucho tráfico de fondo.
        if (proto !== "ICMP" && proto !== "ICMPv6" && ScanWatch.isScanning(ip)
            && remotePorts.indexOf(port) === -1) return

        if (proto === "ICMP" || proto === "ICMPv6") return

        let kind
        if (m[3] === "drop") kind = "blocked"
        else if (port === "22") kind = "ssh"
        else kind = "connect"
        // Tráfico de tus equipos por ZeroTier (Spotify, Deskflow…): ni feed ni
        // aviso. El acceso remoto (VNC, RDP, Telnet…) se avisa venga de donde venga.
        if (kind === "connect" && where(ip) === "ZeroTier" && remotePorts.indexOf(port) === -1) return
        // nmap buscando el equipo: TCP al 80 y al 443 a la vez → un solo "Nmap scan"
        if (proto === "TCP" && (port === "80" || port === "443") && _nmapProbe(t, ip, iface, port)) return
        _add({ t: t, kind: kind, ip: ip, iface: iface, proto: proto, port: port })
    }

    function _add(e) {
        if (e.t < Date.now() - 86400000) return
        // Root lock: ip = quién estaba conectado ("" si no se sabe, p. ej. al
        // rellenar desde el journal), port = sudo/su, note = "sudo refused · playera"
        e.where = e.kind === "rootlock" || e.kind === "rootkill" ? e.note
                : e.kind === "brute" ? (e.ip ? where(e.ip) + " · " : "") + e.note
                : e.kind === "login" ? where(e.ip) + " · " + e.note
                : e.kind === "logout" ? where(e.ip) + " · " + e.note : where(e.ip)
        e.who = known[e.ip] || e.ip || (e.kind === "brute" || e.kind === "rootkill" ? I18n.tr("This PC") : I18n.tr("Remote session"))
        if (e.ip) { _named(e); HostNames.lookup(e.ip) }
        e.service = e.kind === "ping" ? (e.proto === "ICMPv6" ? "ICMPv6" : "ICMP")
                  : e.kind === "scan" || e.kind === "rootlock" || e.kind === "rootkill" || e.kind === "brute" || e.kind === "login" || e.kind === "logout" ? e.proto
                  : (services[e.port] || "") + (services[e.port] ? "" : (e.proto + " " + e.port).trim())
        e.n = e.n || 1
        // Lo mismo (tipo, IP, puerto) en menos de 2 min: se suma al anterior
        const key = e.kind + "|" + e.ip + "|" + (e.kind === "banned" ? "" : e.port)
        const i = events.findIndex(x => x.key === key && e.t - x.t < 120000)
        let list = events.slice()
        const merged = i >= 0
        if (merged) {
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
        if (merged && e.kind === "ping") return
        if (e.t < _start || e.kind === "brute" || e.kind === "rootlock" || e.kind === "login" || e.kind === "logout") return
        if (e.kind === "scan") { _alert(e); return }
        root._later = _later.concat([{ at: Date.now(), e: e }])
        laterTimer.start()
    }

    // ── nmap: descubrimiento de hosts ───────────────────────────────────────
    // nmap comprueba si el equipo está vivo tocando el 80 y el 443 a la vez
    // (además del ping). Si llegan los dos de la misma IP en < 2 s, los
    // "HTTP/HTTPS attempt" sueltos se cambian por un único evento "nmap".
    property var _probes: ({})          // ip → { t, port } del último toque al 80/443
    function _nmapProbe(t, ip, iface, port) {
        // Ya hay un nmap reciente de esa IP: se suma a él
        if (events.some(x => x.kind === "nmap" && x.ip === ip && t - x.t < 60000)) {
            _add({ t: t, kind: "nmap", ip: ip, iface: iface, proto: "TCP", port: "" })
            return true
        }
        const p = _probes[ip]
        const next = Object.assign({}, _probes)
        next[ip] = { t: t, port: port }
        _probes = next
        if (!p || p.port === port || t - p.t > 2000) return false
        // Fuera los sueltos de esa IP (feed y avisos aún pendientes)
        const stray = x => x.ip === ip && (x.port === "80" || x.port === "443") && t - x.t <= 3000
        events = events.filter(x => !stray(x))
        _later = _later.filter(x => !stray(x.e))
        _add({ t: t, kind: "nmap", ip: ip, iface: iface, proto: "TCP", port: "" })
        return true
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
        // Anti-inundación por tipo + IP + servicio/puerto: así cada servicio
        // distinto (Telnet, FTP, VNC…) avisa por su cuenta, y solo se agrupa
        // el MISMO objetivo repetido (el aviso ya muestra ×N). Ventanas: ping
        // 3 s, SSH/banned 15 s, conexión/acceso remoto 15-60 s, bloqueado
        // 5 min POR PUERTO (el mismo puerto de fondo no inunda).
        const ak = e.kind + "|" + e.ip + "|" + (e.service || e.port || "")
        // Ventana corta (8 s) para TODO menos el ping: así cada intento nuevo
        // (SSH, FTP, VNC, nmap, bloqueado…) vuelve a avisar, y dentro de una
        // misma ráfaga (sondas en < 8 s) no inunda. El ping mantiene su 3 s, que
        // además la isla alarga en vivo mientras dure (onPingSeen).
        const gap = e.kind === "ping" ? 3000 : 8000
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
                // El ping y el acceso remoto (VNC, RDP…) avisan siempre; lo demás
                // se calla si esa IP está escaneando (el informe del escaneo manda).
                else if (x.e.kind === "ping" || root._remoteAccess(x.e) || !ScanWatch.isScanning(x.e.ip)) root._alert(x.e)
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
                                                    && ["blocked", "connect", "ssh", "nmap", "banned"].indexOf(x.kind) !== -1))
            root._add({ t: r.last, kind: "scan", ip: r.src, iface: "", port: "", scan: r,
                        proto: r.type + " · " + r.probed + " ports" + (r.banned ? " · " + I18n.tr("all blocked") : "") })
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
                  "-t", "qs-remote-guard", "-g", "^(refused|ended) "]
        stdout: SplitParser {
            onRead: (line) => {
                if (root._rootkill(line)) return
                const m = line.match(/^(\d+)\.\d+\s.*refused (\S+) \(\w+\) for (\S+):/)
                if (m) root._rootlock(Number(m[1]) * 1000, m[2], m[3], "")
            }
        }
    }

    // Sesión root terminada por el root lock (qs-remote-guard --watch / --purge)
    function _rootkill(line) {
        const m = line.match(/^(\d+)\.\d+\s.*?ended (\S+) session \(pid (\d+)\) for (\S+): [^·]*(?:· (.*))?$/)
        if (!m) return false
        _add({ t: Number(m[1]) * 1000, kind: "rootkill", ip: "", iface: "", proto: m[2], port: m[3],
               note: I18n.tr("%1 · %2").arg((m[5] || m[2]).trim()).arg(m[4]) })
        return true
    }
    Process {
        id: rootkillProc
        running: true
        command: ["journalctl", "-f", "-n0", "-q", "--no-pager", "-o", "short-unix",
                  "-t", "qs-remote-guard", "-g", "^ended "]
        stdout: SplitParser { onRead: (line) => root._rootkill(line) }
        onExited: rootkillRestart.start()
    }
    Timer { id: rootkillRestart; interval: 5000; onTriggered: rootkillProc.running = true }

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
