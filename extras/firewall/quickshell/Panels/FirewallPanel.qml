import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Components
import qs.Config
import qs.Services

// Firewall panel, laid out as a security console:
//   header   → protection status + firewall switch
//   gauges   → threat level ring, counters, 24 h activity histogram
//   left     → threat feed (FwActivity) with severity, filters and details
//   right    → root lock, live connections, banned IPs, exposed ports
// Data: Services/Firewall.qml (qs-netwatch), FwActivity, FwBlock.
Popout {
    id: panel
    ns: "qs-firewall"
    // Ancho para tres columnas: todo cabe sin scroll (el feed tiene el suyo)
    cardWidth: 1320
    cardMinWidth: 900
    cardMaxHeight: (screen ? screen.height : 1080) * 0.93
    scrollable: false
    shown: Globals.firewallOpen

    property real now: Date.now()
    Timer {
        interval: 5000
        running: panel.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: panel.now = Date.now()
    }
    function ago(epoch) {
        const s = Math.max(0, panel.now / 1000 - epoch)
        if (s < 60) return I18n.tr("just now")
        if (s < 3600) return Math.floor(s / 60) + "m " + I18n.tr("ago")
        if (s < 86400) return Math.floor(s / 3600) + "h " + I18n.tr("ago")
        return Math.floor(s / 86400) + "d " + I18n.tr("ago")
    }
    function whereColor(w) {
        return w === "Internet" ? Theme.red : w === "Home network" ? Theme.yellow : Theme.green
    }
    // 0..1 en escala logarítmica: 1 evento ya se ve, `full` llena el anillo
    function ringValue(n, full) { return n <= 0 ? 0 : Math.min(1, Math.log(n + 1) / Math.log(full + 1)) }

    readonly property color mono: Theme.withAlpha(Theme.fg, 0.06)
    // Alto para las tres columnas: la tarjeta va a su alto máximo y las
    // columnas se quedan con lo que dejan cabecera, indicadores, gravedad y
    // (si está) la respuesta a amenazas
    readonly property int colsH: Math.max(Theme.dp(240), Math.floor(cardMaxHeight - Theme.space16 * 2
        - hdrCard.implicitHeight - gaugeCard.implicitHeight - sevCard.implicitHeight - Theme.space12 * 3
        - (response.visible ? response.implicitHeight + Theme.space12 : 0)))
    readonly property string monoFont: "JetBrainsMono Nerd Font"

    // ── Cifras de las últimas 24 h ──────────────────────────────────────────
    readonly property var ev: FwActivity.events
    readonly property int nBlocked: ev.filter(e => e.kind === "blocked" || e.kind === "banned").reduce((a, e) => a + e.n, 0)
    readonly property int nScans: ev.filter(e => e.kind === "scan").length
    readonly property int nIntrusion: ev.filter(e => ["ssh", "brute", "rootlock", "banned"].indexOf(e.kind) !== -1
                                                    || (e.kind === "login" && FwActivity.severity(e) === "high"))
                                         .reduce((a, e) => a + e.n, 0)
    readonly property int nLive: Firewall.inbound.filter(e => e.state !== "authenticating").length
    readonly property int nSources: new Set(ev.filter(e => e.ip).map(e => e.ip)).size

    // Nivel de amenaza (0-100): lo de la última hora, ponderado por gravedad (FwActivity)
    readonly property int threat: FwActivity.threat
    readonly property var level: threat >= 60 ? { label: I18n.tr("SEVERE"), color: Theme.red }
                               : threat >= 30 ? { label: I18n.tr("ELEVATED"), color: Theme.orange }
                               : threat >= 10 ? { label: I18n.tr("GUARDED"), color: Theme.yellow }
                               : { label: I18n.tr("LOW"), color: Theme.green }

    // Orígenes con más eventos: [{ ip, name, where, n, rank, kinds }]
    readonly property var topSources: {
        const m = {}
        for (const e of ev) {
            if (!e.ip) continue
            const x = m[e.ip] || (m[e.ip] = { ip: e.ip, n: 0, rank: 0, kinds: {} })
            x.n += e.n
            x.rank = Math.max(x.rank, FwActivity.levels[FwActivity.severity(e)].rank)
            x.kinds[FwActivity.kinds[e.kind] ? FwActivity.kinds[e.kind].label : e.kind] = 1
        }
        return Object.values(m).sort((a, b) => b.rank - a.rank || b.n - a.n).slice(0, 5).map(x => ({
            ip: x.ip, n: x.n, rank: x.rank, where: FwActivity.where(x.ip),
            name: FwActivity.known[x.ip] || HostNames.label(x.ip) || "",
            kinds: Object.keys(x.kinds).slice(0, 3).join(", ")
        }))
    }
    // Servicios / puertos más tocados: [{ name, n, rank }]
    // Lista FIJA de servicios conectables: siempre las mismas filas, en el
    // mismo orden. Cada evento se clasifica por el primer `match` que cumple;
    // si no es ninguno, va al cajón "Other ports". Lo no atacado queda en 0.
    readonly property var svcSpec: [
        { name: I18n.tr("Ping"),       port: "ICMP",     match: e => e.kind === "ping" },
        { name: "SSH",                 port: "TCP 22",   match: e => e.kind === "ssh" || e.kind === "brute" || e.kind === "login" || e.port === "22" },
        { name: "FTP",                 port: "TCP 21",   match: e => e.port === "21" },
        { name: "Telnet",              port: "TCP 23",   match: e => e.port === "23" },
        { name: "SMB",                 port: "TCP 445",  match: e => e.port === "445" || e.port === "139" },
        { name: "RDP",                 port: "TCP 3389", match: e => e.port === "3389" },
        { name: "VNC",                 port: "TCP 5900", match: e => ["5900","5901","5902","5903","5800"].indexOf(e.port) !== -1 },
        { name: "HTTP",                port: "TCP 80",   match: e => e.port === "80" || e.port === "8080" },
        { name: "HTTPS",               port: "TCP 443",  match: e => e.port === "443" },
        { name: I18n.tr("Port scans"), port: "",         match: e => e.kind === "scan" || e.kind === "nmap" },
        { name: I18n.tr("sudo / su"),  port: "",         match: e => e.kind === "rootlock" }
    ]
    readonly property var topServices: {
        const spec = svcSpec
        const rows = spec.map(s => ({ name: s.name, port: s.port, n: 0, rank: 0 }))
        const other = { name: I18n.tr("Other ports"), port: "", n: 0, rank: 0, other: true }
        for (const e of ev) {
            if (e.kind === "logout") continue
            const rank = FwActivity.levels[FwActivity.severity(e)].rank
            let idx = -1
            for (let i = 0; i < spec.length; i++) if (spec[i].match(e)) { idx = i; break }
            const row = idx === -1 ? other : rows[idx]
            row.n += e.n
            row.rank = Math.max(row.rank, rank)
        }
        // Más atacado arriba, menos (y los que están en 0) abajo; el cajón
        // "Other ports" va siempre al final (no es un servicio como tal).
        const sorted = rows.slice()
        sorted.sort(function (a, b) { return b.n - a.n })
        sorted.push(other)
        return sorted
    }
    // Escala las barras al servicio con nombre más atacado, no al cajón de
    // "Otros" (que casi siempre arrasa): así SSH/VNC/FTP… siguen legibles.
    readonly property int topServicesMax: Math.max(1, ...topServices.filter(s => !s.other).map(s => s.n))
    // Exporta los eventos de 24 h a ~/Downloads (JSON, como un SIEM)
    function exportEvents() {
        const file = Settings.home + "/Downloads/firewall-events-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss") + ".json"
        const rows = ev.map(e => ({
            time: new Date(e.t).toISOString(), first: new Date(e.first || e.t).toISOString(),
            severity: FwActivity.severity(e), event: FwActivity.headline(e), kind: e.kind,
            source: e.ip || "", name: e.who, origin: e.where, iface: e.iface || "",
            proto: e.proto || "", port: e.port || "", service: e.service || "", count: e.n,
            mitre: FwActivity.mitre(e)
        }))
        exportFile.path = file
        exportFile.setText(JSON.stringify(rows, null, 2) + "\n")
        Quickshell.execDetached(["notify-send", "-a", "Quickshell", I18n.tr("Firewall events exported"),
                                 rows.length + " " + I18n.tr("events") + " → " + file])
    }
    FileView { id: exportFile; printErrors: false }

    // Eventos por hora (24 barras, la última = esta hora) y su peor gravedad
    readonly property var hours: {
        const b = []
        for (let i = 0; i < 24; i++) b.push({ n: 0, rank: -1 })
        for (const e of ev) {
            const h = Math.floor((panel.now - e.t) / 3600000)
            if (h < 0 || h > 23) continue
            const x = b[23 - h]
            x.n += e.n
            x.rank = Math.max(x.rank, FwActivity.levels[FwActivity.severity(e)].rank)
        }
        return b
    }
    readonly property int hoursMax: Math.max(1, ...hours.map(h => h.n))
    function rankColor(r) {
        return r >= 4 ? Theme.red : r === 3 ? Theme.orange : r === 2 ? Theme.yellow : r === 1 ? Theme.cyan : Theme.fgDim
    }

    // ── Cabecera ────────────────────────────────────────────────────────────
    AiCard {
        id: hdrCard
        Layout.fillHeight: false
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(14)

            // Escudo en un anillo del color del estado
            StatRing {
                implicitWidth: Theme.dp(52); implicitHeight: Theme.dp(52)
                value: 1
                animated: false
                ringWidth: Theme.dp(3)
                tint: !Firewall.firewallInstalled ? Theme.fgMuted : Firewall.firewallOn ? Theme.green : Theme.red
                Text {
                    anchors.centerIn: parent
                    text: "\u{f1a11}"
                    color: parent.tint
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(22)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.dp(2)
                RowLayout {
                    spacing: Theme.dp(10)
                    Text {
                        text: I18n.tr("NETWORK FIREWALL")
                        color: Theme.fg
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize + 3
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Rectangle {
                        readonly property color c: !Firewall.firewallInstalled ? Theme.fgMuted
                                                   : Firewall.firewallOn ? Theme.green : Theme.red
                        implicitWidth: stateText.implicitWidth + Theme.dp(16)
                        implicitHeight: Theme.dp(20)
                        radius: Theme.dp(4)
                        color: Theme.withAlpha(c, 0.14)
                        border.width: 1
                        border.color: Theme.withAlpha(c, 0.5)
                        Text {
                            id: stateText
                            anchors.centerIn: parent
                            text: !Firewall.firewallInstalled ? I18n.tr("NOT INSTALLED")
                                : Firewall.firewallOn ? I18n.tr("PROTECTED") : I18n.tr("UNPROTECTED")
                            color: parent.c
                            font.family: panel.monoFont
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: true
                            font.letterSpacing: 1
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: !Firewall.firewallInstalled ? I18n.tr("Not installed yet: run the installer once with sudo")
                        : (Firewall.firewallOn ? I18n.tr("Policy: default-deny inbound · nftables inet qs_firewall")
                                               : I18n.tr("Off: every open port is reachable"))
                    color: Theme.fgMuted
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 2
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: (panel.ev.length === 1 ? I18n.tr("1 event") : I18n.tr("%1 events").arg(panel.ev.length)) + " · "
                          + (panel.nSources === 1 ? I18n.tr("1 source") : I18n.tr("%1 sources").arg(panel.nSources)) + " · 24h"
                          + (panel.ev.length > 0 ? "  ·  " + I18n.tr("last") + " " + panel.ago(panel.ev[0].t / 1000) : "")
                    color: Theme.fgDim
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 3
                }
            }
            Switch {
                enabled: Firewall.firewallInstalled && !Firewall.fwBusy
                opacity: enabled ? 1 : 0.5
                checked: Firewall.firewallOn
                onColor: Theme.green
                onToggled: Firewall.toggleFirewall()
            }
        }
    }

    // ── Indicadores: nivel de amenaza, contadores e histograma 24 h ────────
    AiCard {
        id: gaugeCard
        Layout.fillHeight: false
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(22)

            // Nivel de amenaza
            Item {
                implicitWidth: Theme.dp(116); implicitHeight: Theme.dp(116)
                StatRing {
                    anchors.fill: parent
                    value: panel.threat / 100
                    ringWidth: Theme.dp(9)
                    tint: panel.level.color
                    animated: panel.shown
                }
                // Anillo fino exterior decorativo
                StatRing {
                    anchors.fill: parent
                    anchors.margins: Theme.dp(16)
                    value: 1
                    animated: false
                    ringWidth: 1
                    tint: Theme.withAlpha(panel.level.color, 0.25)
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: panel.threat
                        color: Theme.fg
                        font.family: panel.monoFont
                        font.pixelSize: Theme.dp(30)
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: panel.level.label
                        color: panel.level.color
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 3
                        font.bold: true
                        font.letterSpacing: 1.5
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.tr("threat level")
                        color: Theme.fgDim
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 4
                    }
                }
            }

            // Contadores en anillos
            Repeater {
                model: [
                    { label: I18n.tr("Blocked"), n: panel.nBlocked, full: 500, color: Theme.cyan },
                    { label: I18n.tr("Scans"), n: panel.nScans, full: 10, color: Theme.red },
                    { label: I18n.tr("Intrusion"), n: panel.nIntrusion, full: 50, color: Theme.orange },
                    { label: I18n.tr("Live"), n: panel.nLive, full: 5, color: Theme.green }
                ]
                Column {
                    required property var modelData
                    spacing: Theme.dp(8)
                    StatRing {
                        anchors.horizontalCenter: parent.horizontalCenter
                        implicitWidth: Theme.dp(70); implicitHeight: Theme.dp(70)
                        value: panel.ringValue(modelData.n, modelData.full)
                        ringWidth: Theme.dp(5)
                        tint: modelData.n > 0 ? modelData.color : Theme.fgDim
                        animated: panel.shown
                        Text {
                            anchors.centerIn: parent
                            text: modelData.n
                            color: modelData.n > 0 ? Theme.fg : Theme.fgMuted
                            font.family: panel.monoFont
                            font.pixelSize: Theme.dp(18)
                            font.bold: true
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label.toUpperCase()
                        color: Theme.fgMuted
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 4
                        font.bold: true
                        font.letterSpacing: 1.5
                    }
                }
            }

            // Histograma: eventos por hora, color = peor gravedad de esa hora
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.dp(6)
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("ACTIVITY · 24H")
                        color: Theme.fgMuted
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 4
                        font.bold: true
                        font.letterSpacing: 1.5
                    }
                    Text {
                        text: I18n.tr("peak %1/h").arg(panel.hoursMax)
                        color: Theme.fgDim
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 4
                    }
                }
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Theme.dp(64)
                    // Rejilla de fondo
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            width: parent.width; height: 1
                            y: Math.round(parent.height * index / 3)
                            color: panel.mono
                        }
                    }
                    Row {
                        anchors.fill: parent
                        spacing: Theme.dp(3)
                        Repeater {
                            model: panel.hours
                            Item {
                                required property var modelData
                                width: (parent.width - 23 * parent.spacing) / 24
                                height: parent.height
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: modelData.n === 0 ? 2 : Math.max(3, parent.height * Math.sqrt(modelData.n / panel.hoursMax))
                                    radius: Theme.dp(2)
                                    color: modelData.n === 0 ? panel.mono : panel.rankColor(modelData.rank)
                                    opacity: modelData.n === 0 ? 1 : 0.85
                                    Behavior on height { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "-24h"; color: Theme.fgDim; font.family: panel.monoFont; font.pixelSize: Theme.fontSize - 4 }
                    Item { Layout.fillWidth: true }
                    Text { text: "-12h"; color: Theme.fgDim; font.family: panel.monoFont; font.pixelSize: Theme.fontSize - 4 }
                    Item { Layout.fillWidth: true }
                    Text { text: I18n.tr("now"); color: Theme.fgDim; font.family: panel.monoFont; font.pixelSize: Theme.fontSize - 4 }
                }
            }
        }
    }

    // ── Desglose por gravedad (24 h) ─────────────────────────────────────────
    AiCard {
        id: sevCard
        Layout.fillHeight: false
        readonly property var counts: {
            const c = { critical: 0, high: 0, medium: 0, low: 0, info: 0 }
            for (const e of panel.ev) c[FwActivity.severity(e)] += e.n
            return c
        }
        readonly property int total: Math.max(1, counts.critical + counts.high + counts.medium + counts.low + counts.info)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(16)
            Text {
                text: I18n.tr("SEVERITY · 24H")
                color: Theme.fgMuted
                font.family: panel.monoFont
                font.pixelSize: Theme.fontSize - 4
                font.bold: true
                font.letterSpacing: 1.5
            }
            // Barra apilada
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.dp(8)
                radius: height / 2
                color: panel.mono
                clip: true
                Row {
                    anchors.fill: parent
                    Repeater {
                        model: ["critical", "high", "medium", "low", "info"]
                        Rectangle {
                            required property string modelData
                            width: parent.width * ((sevCard.counts || {})[modelData] || 0) / (sevCard.total || 1)
                            height: parent.height
                            color: FwActivity.levels[modelData].color
                            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
            Repeater {
                model: ["critical", "high", "medium", "low", "info"]
                Row {
                    required property string modelData
                    spacing: Theme.dp(5)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.dp(7); height: width; radius: Theme.dp(2)
                        color: FwActivity.levels[modelData].color
                    }
                    Text {
                        text: FwActivity.levels[modelData].label + " " + ((sevCard.counts || {})[modelData] || 0)
                        color: Theme.fgMuted
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 3
                    }
                }
            }
        }
    }

    // ── Respuesta a amenazas ────────────────────────────────────────────────
    // Sale con el nivel SEVERE: acciones de un clic (banear atacantes, echar
    // sesiones, apagar SSH, bloquear root, encender el firewall) o todas a la
    // vez (Lockdown). Con los atacantes fuera pasa a "contenida" (verde) y se
    // queda mientras el nivel baja de 30. "Acknowledge" la oculta hasta que
    // llegue algo HIGH nuevo.
    readonly property var toBan: FwActivity.attackers.filter(a => !FwBlock.isBlocked(a.ip))
    readonly property var sessions: Firewall.inbound.filter(e => e.session)
    readonly property bool contained: toBan.length === 0 && sessions.length === 0
    readonly property bool responseShown: FwActivity.lastHigh > FwActivity.ackAt
                                          && (FwActivity.severe || (contained && FwActivity.threat >= 30))
    function lockdown() {
        for (const a of toBan) FwBlock.block(a.ip, 60)
        for (const e of sessions) Firewall.disconnect(e)
        if (Sshd.running && !Sshd.busy) Sshd.toggle()
        if (Firewall.rootlock === "unlocked") Firewall.relock()
        if (Firewall.firewallInstalled && !Firewall.firewallOn && !Firewall.fwBusy) Firewall.toggleFirewall()
        FwActivity.mitigate()
    }
    Rectangle {
        id: response
        readonly property color tint: panel.contained ? Theme.green : Theme.red
        visible: panel.responseShown
        Layout.fillWidth: true
        implicitHeight: respRow.implicitHeight + Theme.dp(28)
        radius: Theme.dp(16)
        color: Theme.withAlpha(tint, 0.07)
        border.width: 1
        border.color: Theme.withAlpha(tint, 0.35)
        Behavior on color { ColorAnimation { duration: 400 } }
        clip: true
        // Franja de color a la izquierda
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Theme.dp(4)
            color: response.tint
        }

        RowLayout {
            id: respRow
            anchors.fill: parent
            anchors.leftMargin: Theme.dp(20)
            anchors.rightMargin: Theme.dp(14)
            anchors.topMargin: Theme.dp(14)
            anchors.bottomMargin: Theme.dp(14)
            spacing: Theme.dp(18)

            // Estado: icono con pulso + título + nivel
            RowLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: Theme.dp(290)
                Layout.maximumWidth: Theme.dp(290)
                spacing: Theme.dp(14)
                Item {
                    implicitWidth: Theme.dp(44); implicitHeight: Theme.dp(44)
                    Rectangle {
                        id: pulse
                        anchors.centerIn: parent
                        width: parent.width; height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: response.tint
                        SequentialAnimation on scale {
                            running: response.visible && panel.shown && !panel.contained
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.7; to: 1.25; duration: 1200; easing.type: Easing.OutCubic }
                        }
                        SequentialAnimation on opacity {
                            running: response.visible && panel.shown && !panel.contained
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.9; to: 0; duration: 1200; easing.type: Easing.OutCubic }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: Theme.dp(36); height: width
                        radius: width / 2
                        color: Theme.withAlpha(response.tint, 0.18)
                        Text {
                            anchors.centerIn: parent
                            text: panel.contained ? "\u{f0565}" : "\u{f0026}"
                            color: response.tint
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.dp(18)
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.dp(3)
                    Text {
                        text: panel.contained ? I18n.tr("THREAT CONTAINED") : I18n.tr("ACTIVE THREAT")
                        color: response.tint
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        font.letterSpacing: 2
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            if (panel.contained) return I18n.tr("Attackers blocked · level decreasing")
                            const a = panel.toBan
                            return a.length === 0 ? I18n.tr("Response required")
                                 : a.slice(0, 2).map(x => (x.name ? x.name + " " : "") + x.ip).join(", ")
                                   + (a.length > 2 ? " +" + (a.length - 2) : "")
                        }
                        color: Theme.fg
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 3
                    }
                    // Medidor del nivel
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.dp(8)
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.dp(4)
                            radius: height / 2
                            color: panel.mono
                            Rectangle {
                                width: parent.width * panel.threat / 100
                                height: parent.height
                                radius: height / 2
                                color: panel.level.color
                                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                            }
                        }
                        Text {
                            text: panel.threat + " · " + panel.level.label
                            color: panel.level.color
                            font.family: panel.monoFont
                            font.pixelSize: Theme.fontSize - 4
                            font.bold: true
                        }
                    }
                }
            }

            // Acciones: una ficha por acción (icono · nombre · estado)
            Repeater {
                model: [
                    { id: "ban", icon: "\u{f0ecc}", label: I18n.tr("Ban attackers"),
                      done: panel.toBan.length === 0,
                      status: panel.toBan.length === 0 ? I18n.tr("All banned") : panel.toBan.length === 1 ? I18n.tr("1 IP · 1 h") : I18n.tr("%1 IPs · 1 h").arg(panel.toBan.length) },
                    { id: "kick", icon: "\u{f0343}", label: I18n.tr("Kick sessions"),
                      done: panel.sessions.length === 0,
                      status: panel.sessions.length === 0 ? I18n.tr("Nobody in") : I18n.tr("%1 active").arg(panel.sessions.length) },
                    { id: "ssh", icon: "\u{f018d}", label: I18n.tr("SSH server"),
                      done: !Sshd.running, status: Sshd.running ? I18n.tr("Running · stop") : I18n.tr("Stopped") },
                    { id: "root", icon: "\u{f033e}", label: I18n.tr("Root access"),
                      done: Firewall.rootlock !== "unlocked", status: Firewall.rootlock === "unlocked" ? I18n.tr("Unlocked · lock") : I18n.tr("Locked") },
                    { id: "fw", icon: "\u{f1a11}", label: I18n.tr("Firewall"),
                      done: Firewall.firewallOn, status: Firewall.firewallOn ? I18n.tr("Enforcing") : I18n.tr("Off · turn on") }
                ]
                Rectangle {
                    id: act
                    required property var modelData
                    readonly property color c: modelData.done ? Theme.green : Theme.red
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.minimumWidth: Theme.dp(96)
                    implicitHeight: Theme.dp(54)
                    radius: Theme.dp(10)
                    color: !modelData.done && actMa.containsMouse ? Theme.withAlpha(c, 0.2) : Theme.withAlpha(Theme.fg, 0.04)
                    border.width: 1
                    border.color: Theme.withAlpha(c, modelData.done ? 0.2 : actMa.containsMouse ? 0.7 : 0.35)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.dp(10)
                        anchors.rightMargin: Theme.dp(8)
                        spacing: Theme.dp(8)
                        Text {
                            text: act.modelData.done ? "\u{f012c}" : act.modelData.icon
                            color: act.c
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.dp(16)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.dp(1)
                            Text {
                                Layout.fillWidth: true
                                text: act.modelData.label
                                color: act.modelData.done ? Theme.fgMuted : Theme.fg
                                elide: Text.ElideRight
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 3
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: act.modelData.status
                                color: act.modelData.done ? Theme.withAlpha(Theme.green, 0.8) : Theme.withAlpha(Theme.red, 0.9)
                                elide: Text.ElideRight
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                    }
                    MouseArea {
                        id: actMa
                        anchors.fill: parent
                        enabled: !act.modelData.done
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            switch (act.modelData.id) {
                            case "ban": for (const a of panel.toBan) FwBlock.block(a.ip, 60); break
                            case "kick": for (const e of panel.sessions) Firewall.disconnect(e); break
                            case "ssh": if (!Sshd.busy) Sshd.toggle(); break
                            case "root": Firewall.relock(); break
                            case "fw": if (!Firewall.fwBusy) Firewall.toggleFirewall(); break
                            }
                        }
                    }
                }
            }

            // Lockdown (todo) · Acknowledge
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: Theme.dp(130)
                Layout.maximumWidth: Theme.dp(130)
                spacing: Theme.dp(6)
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.dp(34)
                    radius: Theme.dp(10)
                    color: panel.contained ? Theme.withAlpha(Theme.green, 0.15)
                         : lockMa.containsMouse ? Qt.lighter(Theme.red, 1.12) : Theme.red
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        anchors.centerIn: parent
                        text: panel.contained ? "\u{f0565}  " + I18n.tr("SECURED") : "\u{f033e}  " + I18n.tr("LOCKDOWN")
                        color: panel.contained ? Theme.green : "white"
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: true
                        font.letterSpacing: 1.5
                    }
                    MouseArea {
                        id: lockMa
                        anchors.fill: parent
                        enabled: !panel.contained
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: panel.lockdown()
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Acknowledge")
                    color: ackMa.containsMouse ? Theme.fg : Theme.fgMuted
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 3
                    font.underline: ackMa.containsMouse
                    MouseArea {
                        id: ackMa
                        anchors.fill: parent
                        anchors.margins: -Theme.dp(4)
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: FwActivity.ackAt = Date.now()
                    }
                }
            }
        }
    }

    // ── Dos columnas: feed de amenazas | estado ─────────────────────────────
    RowLayout {
        // Alto natural: lo marca la columna de estado más alta; el feed se
        // estira para igualarla y desplaza por dentro si hace falta.
        Layout.fillWidth: true
        spacing: Theme.space8

        // ── Feed de amenazas ────────────────────────────────────────────────
        AiCard {
            id: activity
            // Llena el alto que marcan las columnas de estado; no crece con el
            // contenido del feed (la lista desplaza por dentro).
            Layout.fillHeight: true
            Layout.preferredWidth: 46
            property string filter: "all"
            property string open: ""            // id del evento desplegado
            function matches(e) {
                if (filter === "all") return true
                if (filter === "threats") return FwActivity.levels[FwActivity.severity(e)].rank >= 3
                return FwActivity.group(e.kind) === filter
            }
            // Clear solo vacía el feed; las cifras de arriba siguen con las 24 h
            readonly property var shown: FwActivity.events.filter(e => e.t > Settings.fwActivityClearedAt)
            readonly property var items: shown.filter(e => matches(e))

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.dp(8)
                Rectangle {
                    // Punto "en directo"
                    implicitWidth: Theme.dp(8); implicitHeight: Theme.dp(8)
                    radius: width / 2
                    color: Firewall.firewallOn ? Theme.green : Theme.fgDim
                    SequentialAnimation on opacity {
                        running: panel.shown && Firewall.firewallOn
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 900 }
                        NumberAnimation { to: 1; duration: 900 }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("THREAT FEED")
                    color: Theme.fg
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    font.letterSpacing: 1.5
                }
                Text {
                    text: Firewall.firewallOn ? I18n.tr("LIVE") : I18n.tr("PAUSED")
                    color: Firewall.firewallOn ? Theme.green : Theme.fgDim
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 3
                    font.bold: true
                    font.letterSpacing: 1
                }
                TextButton {
                    visible: FwActivity.events.length > 0
                    text: "\u{f0207}  " + I18n.tr("Export")
                    implicitHeight: Theme.dp(24)
                    onClicked: panel.exportEvents()
                }
                TextButton {
                    visible: activity.shown.length > 0
                    text: "\u{f0b5c}  " + I18n.tr("Clear")
                    implicitHeight: Theme.dp(24)
                    onClicked: FwActivity.clear()
                }
            }

            // Filtros
            Flow {
                Layout.fillWidth: true
                spacing: Theme.dp(4)
                Repeater {
                    model: [
                        { id: "all", label: I18n.tr("All") },
                        { id: "threats", label: I18n.tr("High+") },
                        { id: "ping", label: I18n.tr("Ping") },
                        { id: "ssh", label: "SSH" },
                        { id: "connect", label: I18n.tr("Connections") },
                        { id: "blocked", label: I18n.tr("Blocked") },
                        { id: "scan", label: I18n.tr("Scans") },
                        { id: "brute", label: I18n.tr("Brute force") },
                        { id: "login", label: I18n.tr("Logins") },
                        { id: "rootlock", label: I18n.tr("Root") }
                    ]
                    Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool sel: activity.filter === modelData.id
                        readonly property int count: modelData.id === "all" ? activity.shown.length
                            : modelData.id === "threats" ? activity.shown.filter(e => FwActivity.levels[FwActivity.severity(e)].rank >= 3).length
                            : activity.shown.filter(e => FwActivity.group(e.kind) === modelData.id).length
                        implicitWidth: chipText.implicitWidth + Theme.dp(14)
                        implicitHeight: Theme.dp(22)
                        radius: Theme.dp(4)
                        color: sel ? Theme.withAlpha(Theme.accent, 0.18) : chipMa.containsMouse ? panel.mono : "transparent"
                        border.width: 1
                        border.color: sel ? Theme.withAlpha(Theme.accent, 0.6) : panel.mono
                        Behavior on color { ColorAnimation { duration: Theme.animFast } }
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData.label + (chip.count > 0 ? " " + chip.count : "")
                            color: chip.sel ? Theme.accent : chip.count > 0 ? Theme.fg : Theme.fgDim
                            font.family: panel.monoFont
                            font.pixelSize: Theme.fontSize - 3
                            font.bold: chip.sel
                        }
                        MouseArea {
                            id: chipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { activity.filter = chip.modelData.id; feedList.positionViewAtBeginning() }
                        }
                    }
                }
            }

            // Cabecera de columnas
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.dp(4)
                spacing: Theme.dp(10)
                visible: activity.items.length > 0
                Repeater {
                    model: [
                        { t: I18n.tr("TIME"), w: 62 }, { t: I18n.tr("SEV"), w: 40 },
                        { t: I18n.tr("EVENT"), w: -1 }, { t: I18n.tr("SOURCE"), w: 150 }
                    ]
                    Text {
                        required property var modelData
                        Layout.preferredWidth: modelData.w > 0 ? Theme.dp(modelData.w) : -1
                        Layout.fillWidth: modelData.w < 0
                        text: modelData.t
                        color: Theme.fgDim
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 4
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: panel.mono
                visible: activity.items.length > 0
            }

            ColumnLayout {
                visible: activity.items.length === 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.dp(160)
                spacing: Theme.dp(8)
                Item { Layout.fillHeight: true }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Firewall.firewallOn ? "\u{f0565}" : "\u{f0a3e}"
                    color: Firewall.firewallOn ? Theme.withAlpha(Theme.green, 0.6) : Theme.fgDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(34)
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: !Firewall.firewallOn ? I18n.tr("FIREWALL OFF")
                        : activity.filter !== "all" && activity.shown.length > 0 ? I18n.tr("NO MATCHING EVENTS")
                        : I18n.tr("ALL CLEAR")
                    color: Theme.fg
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                    font.letterSpacing: 2
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.dp(30)
                    Layout.rightMargin: Theme.dp(30)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: !Firewall.firewallOn ? I18n.tr("Turn the firewall on to monitor who pings or connects to your PC.")
                        : !FwActivity.rulesReady ? I18n.tr("Only blocked traffic is logged until the new firewall rules are installed (scripts/qs-firewall.nft).")
                        : I18n.tr("Monitoring pings, SSH, VNC, Telnet, FTP and every other connection attempt, scans, brute force, logins and root refusals.")
                    color: Theme.fgMuted
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 3
                }
                Item { Layout.fillHeight: true }
            }

            // Lista con su propio scroll (rueda / arrastrar)
            ListView {
                id: feedList
                Layout.fillWidth: true
                // Llena el hueco de la tarjeta (alto fijo marcado por las
                // columnas de estado) y desplaza por dentro si sobra contenido;
                // su alto no depende del nº de eventos, así el panel no crece.
                Layout.fillHeight: true
                Layout.preferredHeight: Theme.dp(200)
                visible: count > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: activity.items
                // Barra de scroll fina a la derecha
                Rectangle {
                    visible: feedList.contentHeight > feedList.height + 1
                    anchors.right: parent.right
                    y: feedList.visibleArea.yPosition * feedList.height
                    width: Theme.dp(3)
                    height: Math.max(Theme.dp(20), feedList.visibleArea.heightRatio * feedList.height)
                    radius: width / 2
                    color: Theme.withAlpha(Theme.fg, feedList.moving ? 0.35 : 0.15)
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                }
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property var sev: FwActivity.levels[FwActivity.severity(modelData)]
                    readonly property bool isOpen: activity.open === modelData.id
                    readonly property string detail: {
                        const e = modelData, out = []
                        out.push(I18n.tr("Origin") + ": " + e.where + (e.iface ? " · via " + e.iface : ""))
                        if (e.ip) out.push(I18n.tr("Address") + ": " + e.ip + (e.port && /^\d+$/.test(e.port) ? " → " + I18n.tr("port") + " " + e.port + "/" + e.proto : ""))
                        if (e.n > 1) out.push(I18n.tr("Count") + ": ×" + e.n + " · " + I18n.tr("first") + " " + Qt.formatDateTime(new Date(e.first), "hh:mm:ss"))
                        const t = FwActivity.mitre(e)
                        if (t) out.push("MITRE ATT&CK: " + t)
                        const r = e.scan
                        if (r) {
                            out.push(I18n.tr("Found open") + ": " + (r.open.length > 0 ? FwActivity.portList(r.open, 12) : I18n.tr("none")))
                            if (r.closed.length > 0) out.push(I18n.tr("Closed") + ": " + FwActivity.portList(r.closed, 12))
                            out.push(I18n.tr("Filtered") + ": " + r.filtered.length + " · " + Math.max(1, Math.round((r.last - r.first) / 1000)) + " s")
                        }
                        return out.join("\n")
                    }
                    width: ListView.view.width - Theme.dp(8)
                    implicitHeight: rowCol.implicitHeight + Theme.dp(10)
                    radius: Theme.dp(6)
                    color: isOpen ? panel.mono : rowMa.containsMouse ? Theme.withAlpha(Theme.fg, 0.035) : "transparent"
                    // Barra de gravedad a la izquierda
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: Theme.dp(5)
                        anchors.bottomMargin: Theme.dp(5)
                        width: 2
                        radius: 1
                        color: row.sev.color
                        opacity: row.sev.rank >= 2 ? 1 : 0.4
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: activity.open = row.isOpen ? "" : row.modelData.id
                    }
                    ColumnLayout {
                        id: rowCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.dp(8)
                        anchors.rightMargin: Theme.dp(6)
                        spacing: Theme.dp(4)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.dp(10)
                            Text {
                                Layout.preferredWidth: Theme.dp(54)
                                text: Qt.formatDateTime(new Date(row.modelData.t), "hh:mm:ss")
                                color: Theme.fgMuted
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 3
                                font.features: { "tnum": 1 }
                            }
                            Rectangle {
                                Layout.preferredWidth: Theme.dp(40)
                                implicitHeight: Theme.dp(16)
                                radius: Theme.dp(3)
                                color: Theme.withAlpha(row.sev.color, 0.15)
                                Text {
                                    anchors.centerIn: parent
                                    text: row.sev.label
                                    color: row.sev.color
                                    font.family: panel.monoFont
                                    font.pixelSize: Theme.fontSize - 5
                                    font.bold: true
                                    font.letterSpacing: 0.5
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: FwActivity.headline(row.modelData) + (row.modelData.n > 1 ? "  ×" + row.modelData.n : "")
                                color: Theme.fg
                                elide: Text.ElideRight
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: row.sev.rank >= 3
                            }
                            Text {
                                Layout.preferredWidth: Theme.dp(150)
                                horizontalAlignment: Text.AlignRight
                                text: row.modelData.who
                                color: panel.whereColor(FwActivity.where(row.modelData.ip || ""))
                                elide: Text.ElideMiddle
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 3
                            }
                        }
                        RowLayout {
                            visible: row.isOpen && !!row.modelData.ip
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.dp(114)
                            spacing: Theme.dp(6)
                            TextButton {
                                visible: !FwActivity.known[row.modelData.ip] && !FwBlock.isBlocked(row.modelData.ip)
                                text: "\u{f0ecc}  " + I18n.tr("Ban 1 h")
                                implicitHeight: Theme.dp(22)
                                onClicked: FwBlock.block(row.modelData.ip, 60)
                            }
                            TextButton {
                                text: "\u{f018f}  " + I18n.tr("Copy IP")
                                implicitHeight: Theme.dp(22)
                                onClicked: Quickshell.execDetached(["wl-copy", row.modelData.ip])
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Text {
                            visible: row.isOpen
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.dp(114)
                            Layout.bottomMargin: Theme.dp(2)
                            text: row.detail
                            color: Theme.fgMuted
                            wrapMode: Text.Wrap
                            lineHeight: 1.2
                            font.family: panel.monoFont
                            font.pixelSize: Theme.fontSize - 3
                        }
                    }
                }
            }
        }

        // ── Estado en dos columnas equilibradas, cada tarjeta a su alto
        // natural (sin scroll propio; el feed tiene el suyo). Columna A.
        ColumnLayout {
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignTop
            Layout.fillWidth: true
            Layout.preferredWidth: 27
            spacing: Theme.space8

            // Root lock (install-rootlock.sh): sin root mientras haya alguien conectado
            AiCard {
                Layout.fillWidth: true
                Layout.fillHeight: false
                FwSectionTitle { text: I18n.tr("ROOT LOCK"); dot: Firewall.rootlock === "locked" ? Theme.red
                    : Firewall.rootlock === "unlocked" ? Theme.yellow : Firewall.rootlock === "armed" ? Theme.green : Theme.fgDim
                    value: Firewall.rootlock.toUpperCase() }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Firewall.rootlock === "unlocked"
                          ? I18n.tr("Unlocked from the island: sudo works for %1 more min")
                              .arg(Math.max(1, Math.ceil((Firewall.rootlockUntil - panel.now / 1000) / 60)))
                        : Firewall.rootlock === "locked" ? I18n.tr("Someone is connected: sudo, su and pkexec are blocked")
                        : Firewall.rootlock === "armed" ? I18n.tr("Ready: root gets blocked as soon as someone connects")
                        : I18n.tr("Not installed: run install-rootlock.sh as root")
                    color: Theme.fgMuted
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 3
                }
                // Botones que pasan a otra línea si no caben en la tarjeta
                Flow {
                    Layout.fillWidth: true
                    visible: !panel.rootPwOpen && (Firewall.rootlock !== "off")
                    spacing: Theme.dp(6)
                    // Cierra el desbloqueo y termina las sesiones root abiertas (sudo -i, su…)
                    TextButton {
                        text: "\u{f0a7a}  " + I18n.tr("End root shells")
                        implicitHeight: Theme.dp(24)
                        onClicked: Firewall.relock()
                    }
                    TextButton {
                        visible: Firewall.rootlock === "unlocked"
                        text: "\u{f033e}  " + I18n.tr("Lock now")
                        implicitHeight: Theme.dp(24)
                        onClicked: Firewall.relock()
                    }
                    // Igual que el Allow de la isla: tu contraseña → root abierto unos minutos
                    TextButton {
                        visible: Firewall.rootlock === "locked" || Firewall.rootlock === "armed"
                        text: "\u{f0fc6}  " + I18n.tr("Allow %1 min").arg(Island.rootUnlockMin)
                        primary: Firewall.rootlock === "locked"
                        implicitHeight: Theme.dp(24)
                        onClicked: {
                            panel.rootPwOpen = true
                            panel.rootPwMsg = ""
                            rootPwField.forceFocus()
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: panel.rootPwOpen
                    spacing: Theme.dp(6)
                    TextField {
                        id: rootPwField
                        Layout.fillWidth: true
                        label: panel.rootPwMsg !== "" ? panel.rootPwMsg : I18n.tr("Your password to unlock root")
                        password: true
                        invalid: panel.rootPwMsg !== ""
                        value: panel.rootPw
                        onEdited: (t) => panel.rootPw = t
                        onAccepted: panel.rootUnlock()
                        onCanceled: panel.rootPwClose()
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Item { Layout.fillWidth: true }
                        TextButton {
                            text: I18n.tr("Cancel")
                            onClicked: panel.rootPwClose()
                        }
                        TextButton {
                            text: Firewall.unlockBusy ? I18n.tr("Checking…") : I18n.tr("Allow")
                            primary: true
                            onClicked: panel.rootUnlock()
                        }
                    }
                }
            }

            // Quién está conectado ahora
            AiCard {
                Layout.fillWidth: true
                Layout.fillHeight: false
                FwSectionTitle {
                    text: I18n.tr("LIVE SESSIONS")
                    dot: panel.nLive > 0 ? Theme.green : Theme.fgDim
                    value: String(panel.nLive)
                }
                Text {
                    visible: Firewall.inbound.length === 0
                    text: I18n.tr("No inbound sessions.")
                    color: Theme.fgMuted
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 3
                }
                Repeater {
                    model: Firewall.inbound
                    FwRow {
                        required property var modelData
                        // SSH aún en la contraseña: todavía no ha entrado
                        readonly property bool signingIn: modelData.state === "authenticating"
                        dotColor: signingIn ? Theme.yellow : panel.whereColor(modelData.where)
                        title: modelData.ip + (signingIn ? "  ·  " + I18n.tr("signing in…") : "")
                        subtitle: (signingIn ? I18n.tr("At the password prompt") + " · " : "")
                                  + modelData.where + " · port " + modelData.rport
                        tag: modelData.service
                        tagColor: Theme.accent
                        // Logins SSH de este usuario: cerrar la sesión (lo echa)
                        actionText: modelData.session ? "\u{f0343}  " + I18n.tr("Kick") : ""
                        onActionClicked: Firewall.disconnect(modelData)
                    }
                }
            }

            // Quién más ha tocado el equipo (24 h)
            AiCard {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: panel.topSources.length > 0
                FwSectionTitle {
                    text: I18n.tr("TOP SOURCES")
                    dot: Theme.orange
                    value: I18n.tr("24H")
                }
                Repeater {
                    model: panel.topSources
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.dp(8)
                        Rectangle {
                            implicitWidth: Theme.dp(7); implicitHeight: Theme.dp(7)
                            radius: width / 2
                            color: panel.rankColor(modelData.rank)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name ? modelData.name + " · " + modelData.ip : modelData.ip
                                color: Theme.fg
                                elide: Text.ElideRight
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 2
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.where + " · " + modelData.kinds
                                color: Theme.fgMuted
                                elide: Text.ElideRight
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 4
                            }
                        }
                        Text {
                            text: modelData.n
                            color: Theme.fg
                            font.family: panel.monoFont
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                        TextButton {
                            visible: !FwActivity.known[modelData.ip]
                            text: FwBlock.isBlocked(modelData.ip) ? I18n.tr("Banned") : I18n.tr("Ban")
                            enabled: !FwBlock.isBlocked(modelData.ip)
                            implicitHeight: Theme.dp(22)
                            onClicked: FwBlock.block(modelData.ip, 60)
                        }
                    }
                }
            }

            // IPs bloqueadas desde la barra (FwBlock), cada una un rato.
            // Debajo de Top Sources (misma columna): quién sigue vetado.
            AiCard {
                Layout.fillWidth: true
                id: blockedCard
                Layout.fillHeight: false
                visible: FwBlock.blocked.length > 0
                Component.onCompleted: FwBlock.refresh()
                property real now: Date.now()
                Timer { interval: 30000; running: blockedCard.visible; repeat: true; onTriggered: blockedCard.now = Date.now() }
                FwSectionTitle {
                    text: I18n.tr("BANNED HOSTS")
                    dot: Theme.red
                    value: String(FwBlock.blocked.length)
                }
                Repeater {
                    model: FwBlock.blocked
                    FwRow {
                        required property var modelData
                        dotColor: Theme.red
                        title: FwActivity.known[modelData.ip] || modelData.ip
                        subtitle: I18n.tr(FwActivity.where(modelData.ip)) + " · "
                                  + I18n.tr("%1 min left").arg(Math.max(1, Math.ceil((modelData.expires - blockedCard.now) / 60000)))
                        removable: true
                        onRemoveClicked: FwBlock.unblock(modelData.ip)
                    }
                }
            }

        }
        // Columna B. Tope de alto = lo que dejan cabecera/indicadores: si la
        // superficie de ataque no cabe, la tarjeta (fillHeight) se comprime y
        // su lista desplaza por dentro, en vez de estirar el panel hacia abajo.
        ColumnLayout {
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignTop
            Layout.maximumHeight: panel.colsH
            Layout.fillWidth: true
            Layout.preferredWidth: 27
            spacing: Theme.space8

            // Servicios más atacados (24 h). Comparte el alto con la superficie
            // de ataque: como van ordenados (más atacado arriba), lo importante
            // queda siempre visible y la lista desplaza por dentro para el resto.
            AiCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.dp(170)
                visible: panel.topServices.length > 0
                FwSectionTitle {
                    text: I18n.tr("TARGETED SERVICES")
                    dot: Theme.cyan
                    value: I18n.tr("24H")
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: contentHeight
                    Layout.minimumHeight: 0
                    clip: true
                    interactive: contentHeight > height + 0.5
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 6000
                    ScrollIndicator.vertical: ScrollIndicator {}
                    spacing: Theme.dp(8)
                    model: panel.topServices
                    delegate: ColumnLayout {
                        required property var modelData
                        readonly property bool hit: modelData.n > 0
                        width: ListView.view.width
                        spacing: Theme.dp(3)
                        opacity: hit ? 1 : 0.42       // lo no atacado queda apagado
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.dp(6)
                            Text {
                                text: modelData.name
                                color: Theme.fg
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 3
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: (modelData.port || "") !== ""
                                text: modelData.port
                                color: Theme.fgDim
                                elide: Text.ElideRight
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 4
                            }
                            Item { Layout.fillWidth: (modelData.port || "") === "" }
                            Text {
                                text: modelData.n
                                color: hit ? Theme.fg : Theme.fgMuted
                                font.family: panel.monoFont
                                font.pixelSize: Theme.fontSize - 3
                                font.bold: true
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.dp(4)
                            radius: height / 2
                            color: panel.mono
                            Rectangle {
                                width: Math.min(1, modelData.n / panel.topServicesMax) * parent.width
                                height: parent.height
                                radius: height / 2
                                color: modelData.other ? Theme.fgDim : panel.rankColor(modelData.rank)
                            }
                        }
                    }
                }
            }



            // Puertos abiertos: superficie expuesta. fillHeight para absorber
            // el alto que sobra (y comprimirse si la columna llega a su tope).
            AiCard {
                Layout.fillWidth: true
                id: surfaceCard
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.dp(190)
                readonly property int nOpen: Firewall.listening.filter(l => l.reach === "open").length
                FwSectionTitle {
                    text: I18n.tr("ATTACK SURFACE")
                    dot: Firewall.newPorts.length > 0 || surfaceCard.nOpen > 0 ? Theme.yellow : Theme.green
                    value: Firewall.newPorts.length > 0 ? Firewall.newPorts.length + " " + I18n.tr("NEW")
                                                        : surfaceCard.nOpen + " " + I18n.tr("EXPOSED")
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: {
                        const n = r => Firewall.listening.filter(l => l.reach === r).length
                        return I18n.tr("%1 reachable · %2 limited · %3 blocked")
                            .arg(n("open")).arg(n("limited")).arg(n("blocked"))
                    }
                    color: Theme.fgMuted
                    font.family: panel.monoFont
                    font.pixelSize: Theme.fontSize - 3
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: Firewall.newPorts.length > 0
                    Text {
                        Layout.fillWidth: true
                        text: I18n.tr("New listening ports. Trust the ones you expect.")
                        color: Theme.yellow
                        wrapMode: Text.WordWrap
                        font.family: panel.monoFont
                        font.pixelSize: Theme.fontSize - 3
                    }
                    TextButton {
                        text: I18n.tr("Trust all")
                        implicitHeight: Theme.dp(24)
                        onClicked: Firewall.trustAll()
                    }
                }
                ListView {
                    id: surfaceList
                    Layout.fillWidth: true
                    // Quiere mostrarlos todos, pero puede encogerse (minimumHeight 0)
                    // cuando la columna llega a su tope: entonces desplaza por dentro.
                    Layout.fillHeight: true
                    Layout.preferredHeight: contentHeight
                    Layout.minimumHeight: 0
                    clip: true
                    interactive: contentHeight > height + 0.5
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 6000
                    spacing: Theme.dp(8)
                    ScrollIndicator.vertical: ScrollIndicator {}
                    // Solo lo alcanzable (los bloqueados ya cuentan en el resumen); nuevos siempre
                    model: Firewall.listening.filter(l => l.reach !== "blocked" || Firewall.isNewPort(l)).sort((a, b) =>
                        ["open", "limited", "blocked"].indexOf(a.reach) - ["open", "limited", "blocked"].indexOf(b.reach))
                    delegate: FwRow {
                        required property var modelData
                        readonly property bool isNew: Firewall.isNewPort(modelData)
                        readonly property bool isSsh: modelData.proto === "tcp" && modelData.port === "22"
                        width: ListView.view.width
                        dotColor: isNew || modelData.reach === "open" ? Theme.yellow
                                : modelData.reach === "limited" ? Theme.green : Theme.fgDim
                        title: (modelData.process || I18n.tr("Unknown")) + (isNew ? "  ·  " + I18n.tr("new") : "")
                        subtitle: modelData.reach_text || ""
                        tag: modelData.proto.toUpperCase() + " " + modelData.port
                        tagColor: isNew ? Theme.yellow : Theme.fgDim
                        actionText: isNew ? I18n.tr("Trust")
                                  : isSsh && Sshd.running && !Sshd.busy ? I18n.tr("Turn off") : ""
                        onActionClicked: {
                            if (isNew) Firewall.trustPort(modelData)
                            else if (isSsh) Sshd.toggle()
                        }
                    }
                }
            }
        }
    }

    property bool rootPwOpen: false
    property string rootPw: ""
    property string rootPwMsg: ""
    property int rootPwTries: 0
    function rootPwClose() {
        rootPwOpen = false
        rootPw = ""
        rootPwMsg = ""
        rootPwTries = 0
    }
    function rootUnlock() {
        if (rootPw !== "" && Firewall.unlockRoot(rootPw, Island.rootUnlockMin, "panel")) rootPw = ""
    }
    onShownChanged: if (!shown) rootPwClose()
    Connections {
        target: Firewall
        function onUnlockResult(code, err, from) {
            if (from !== "panel") return
            if (code === 0) { panel.rootPwClose(); return }
            if (code === 10 && ++panel.rootPwTries < 3) {
                panel.rootPwMsg = I18n.tr("Wrong password · %1 left").arg(3 - panel.rootPwTries)
                rootPwField.forceFocus()
                return
            }
            panel.rootPwClose()
            Quickshell.execDetached(["notify-send", "-a", "Quickshell", I18n.tr("Root lock"),
                code === 10 ? I18n.tr("Wrong password: root stays locked")
                : code === 11 ? I18n.tr("Only from this desktop") : (err || "exit code " + code)])
        }
    }
}
