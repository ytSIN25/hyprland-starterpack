pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Escaneo de puertos (nmap y compañía): sigue los paquetes nuevos que
// registra el firewall del shell (scripts/qs-firewall.nft), tanto los que
// deja pasar ("qs-fw-in:") como los que descarta ("qs-fw-drop:") y los
// sigilosos FIN/NULL/Xmas ("qs-fw-stealth:", siempre descartados). El log va
// limitado por IP de origen, así que un escaneo rápido deja ~150 puertos en
// el journal, de sobra para verlo.
//
// Una IP que toca ≥ 15 puertos distintos en 60 s es un escaneo. Cuando lleva
// 4 s callada se cierra el informe y se emite scan(r), una vez cada 10 min
// por IP, con lo mismo que vería nmap desde el otro lado:
//   open     dejado pasar y con algo escuchando  → el escáner lo encontró
//   closed   dejado pasar pero sin nada escuchando (RST)
//   filtered descartado por el firewall (el escáner no ve nada)
// r = { src, first, last (ms), probed, tcp, udp, proto, type, stealth,
//       open: [{port, proto}], closed: [...], filtered: [...] }
// type: tipo de escaneo según las flags TCP: "SYN" (SYN crudo de nmap -sS,
// ventana 1024), "Connect" (connect() normal, nmap -sT), "ACK", "FIN",
// "NULL", "Xmas" o "UDP". stealth = SYN/FIN/NULL/Xmas (los que nmap llama
// "stealth": no completan la conexión). title(r) → "SYN stealth scan".
Singleton {
    id: root

    signal scan(var r)

    readonly property int threshold: 15
    readonly property int quietMs: 4000
    property var _hits: ({})            // src → { start, last, ports: {"TCP/22": {port, proto, allowed}}, types: {SYN: n} }
    property var _alerted: ({})         // src → epoch ms del último aviso
    property var _pending: []           // informes esperando a `ss` (puertos a la escucha)
    property var _reported: ({})        // src → ms del informe (sus reintentos tardíos siguen siendo del escaneo)

    // ¿Esa IP está escaneando ahora mismo? (FwActivity no apunta sus
    // paquetes uno a uno mientras tanto)
    function title(r) {
        return r.stealth ? I18n.tr("%1 stealth scan").arg(r.type) : I18n.tr("%1 scan").arg(r.type)
    }

    function isScanning(src) {
        if (Date.now() - (_reported[src] || 0) < 60000) return true
        const e = _hits[src]
        return !!e && Object.keys(e.ports).length >= threshold && Date.now() - e.last < 60000
    }

    // Flags TCP del log del kernel ("RES=0x00 URG PSH FIN URGP=0") → tipo
    function _type(line, proto) {
        if (proto === "UDP") return "UDP"
        const f = ((line.match(/RES=0x[0-9a-f]+ ((?:[A-Z]+ )*)URGP=/) || [])[1] || "").trim().split(" ").filter(x => x)
        if (f.includes("SYN")) return /\bWINDOW=1024\b/.test(line) ? "SYN" : "Connect"
        if (f.includes("FIN")) return f.includes("URG") && f.includes("PSH") ? "Xmas" : "FIN"
        if (f.includes("ACK")) return "ACK"
        return f.length === 0 ? "NULL" : f.join("/")
    }

    function _line(line) {
        const m = line.match(/qs-fw-(in|drop|stealth):/)
        const src = (line.match(/\bSRC=(\S+)/) || [])[1]
        const dpt = (line.match(/\bDPT=(\d+)/) || [])[1]
        const proto = (line.match(/\bPROTO=(\S+)/) || [])[1] || "?"
        // Solo TCP/UDP con puerto (ping e IGMP no cuentan)
        if (!m || !src || !dpt || src === "0.0.0.0") return
        const now = Date.now()
        const h = Object.assign({}, _hits)
        let e = h[src]
        if (!e || now - e.start > 60000 && Object.keys(e.ports).length < threshold)
            e = { start: now, last: now, ports: {}, types: {} }
        else
            e = { start: e.start, last: now, ports: Object.assign({}, e.ports), types: Object.assign({}, e.types) }
        const t = _type(line, proto)
        e.types[t] = (e.types[t] || 0) + 1
        const k = proto + "/" + dpt
        // Un puerto que alguna vez pasó cuenta como permitido
        const allowed = m[1] === "in" || (e.ports[k] ? e.ports[k].allowed : false)
        e.ports[k] = { port: Number(dpt), proto: proto, allowed: allowed }
        h[src] = e
        root._hits = h
        quiet.restart()
    }

    // Cierra los escaneos que llevan quietMs sin paquetes nuevos
    Timer {
        id: quiet
        interval: root.quietMs + 200
        onTriggered: root._sweep()
    }
    function _sweep() {
        const now = Date.now(), h = {}
        let again = false
        for (const src in _hits) {
            const e = _hits[src]
            const n = Object.keys(e.ports).length
            if (now - e.last < quietMs) { h[src] = e; again = true; continue }
            if (n >= threshold) {
                const r = Object.assign({}, _reported)
                r[src] = now
                root._reported = r
            }
            if (n >= threshold && now - (_alerted[src] || 0) > 10 * 60000) {
                const a = Object.assign({}, _alerted)
                a[src] = now
                root._alerted = a
                root._pending = _pending.concat([{ src: src, e: e }])
            }
            // Por debajo del umbral se guarda hasta que caduque la ventana de 60 s
            else if (n < threshold && now - e.start < 60000) h[src] = e
        }
        root._hits = h
        if (again) quiet.restart()
        if (_pending.length > 0 && !listenProc.running) listenProc.running = true
    }

    // Puertos a la escucha fuera de loopback, para separar open de closed
    Process {
        id: listenProc
        command: ["ss", "-Hlntu"]
        stdout: StdioCollector {
            onStreamFinished: {
                const listening = {}
                for (const l of this.text.split("\n")) {
                    const f = l.trim().split(/\s+/)
                    if (f.length < 5) continue
                    const local = f[4]
                    const port = local.slice(local.lastIndexOf(":") + 1)
                    const addr = local.slice(0, local.lastIndexOf(":"))
                    if (/^(127\.|\[::1\])/.test(addr)) continue
                    listening[(f[0] === "udp" ? "UDP" : "TCP") + "/" + port] = true
                }
                const todo = root._pending
                root._pending = []
                for (const p of todo) root.scan(root._report(p.src, p.e, listening))
            }
        }
    }

    function _report(src, e, listening) {
        const r = { src: src, first: e.start, last: e.last, open: [], closed: [], filtered: [], tcp: 0, udp: 0 }
        const byPort = (a, b) => a.port - b.port
        for (const k in e.ports) {
            const p = e.ports[k]
            if (p.proto === "UDP") r.udp++
            else r.tcp++
            if (!p.allowed) r.filtered.push(p)
            else if (listening[k]) r.open.push(p)
            else r.closed.push(p)
        }
        r.open.sort(byPort); r.closed.sort(byPort); r.filtered.sort(byPort)
        r.probed = r.tcp + r.udp
        r.proto = r.tcp >= r.udp ? "TCP" : "UDP"
        r.type = Object.keys(e.types).sort((a, b) => e.types[b] - e.types[a])[0] || r.proto
        r.stealth = r.type === "SYN" || r.type === "FIN" || r.type === "NULL" || r.type === "Xmas"
        return r
    }

    Process {
        id: kmsg
        running: true
        command: ["journalctl", "-k", "-f", "-n0", "-q", "-o", "cat", "-g", "qs-fw-(in|drop|stealth):"]
        stdout: SplitParser { onRead: (line) => root._line(line) }
        onExited: restart.start()
    }
    Timer {
        id: restart
        interval: 5000
        onTriggered: kmsg.running = true
    }
}
