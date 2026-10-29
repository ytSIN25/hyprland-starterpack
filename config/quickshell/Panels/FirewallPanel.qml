import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Config
import qs.Services

// Firewall panel: firewall switch, root lock, activity log (FwActivity), blocked IPs,
// who is connected right now, traffic the firewall blocked and the ports that are open.
// Data: Services/Firewall.qml (qs-netwatch).
Popout {
    id: panel
    ns: "qs-firewall"
    cardWidth: 520
    cardMinWidth: 400
    scrollable: true
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

    // ── Switches ────────────────────────────────────────────────────────────
    AiCard {
        Layout.fillHeight: false

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(12)
            Text {
                text: "\u{f1a11}"
                color: !Firewall.firewallInstalled ? Theme.fgMuted : Firewall.firewallOn ? Theme.green : Theme.red
                font.family: Theme.fontFamily
                font.pixelSize: Theme.dp(26)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.dp(2)
                Text {
                    text: I18n.tr("Firewall")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: !Firewall.firewallInstalled ? I18n.tr("Not installed yet: run the installer once with sudo")
                        : Firewall.firewallOn ? I18n.tr("On: unknown connections are blocked")
                        : I18n.tr("Off: every open port is reachable")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
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

    // ── Root lock (install-rootlock.sh): no root while someone is connected
    AiCard {
        Layout.fillHeight: false
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(12)
            Text {
                text: Firewall.rootlock === "off" || Firewall.rootlock === "unlocked" ? "\u{f0fc6}" : "\u{f033e}"   // lock-open / lock
                color: Firewall.rootlock === "locked" ? Theme.red
                     : Firewall.rootlock === "unlocked" ? Theme.yellow
                     : Firewall.rootlock === "armed" ? Theme.green : Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.dp(24)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.dp(2)
                Text {
                    text: I18n.tr("Root lock")
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                    font.bold: true
                }
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
            TextButton {
                visible: Firewall.rootlock === "unlocked"
                text: "\u{f033e}  " + I18n.tr("Lock now")
                implicitHeight: Theme.dp(26)
                onClicked: Firewall.relock()
            }
            // Same as the island's Allow: your password → root open for a few min
            TextButton {
                visible: (Firewall.rootlock === "locked" || Firewall.rootlock === "armed") && !panel.rootPwOpen
                text: "\u{f0fc6}  " + I18n.tr("Allow %1 min").arg(Island.rootUnlockMin)
                primary: Firewall.rootlock === "locked"
                implicitHeight: Theme.dp(26)
                onClicked: {
                    panel.rootPwOpen = true
                    panel.rootPwMsg = ""
                    rootPwField.forceFocus()
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: panel.rootPwOpen
            spacing: Theme.dp(8)
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
            TextButton {
                Layout.alignment: Qt.AlignBottom
                text: I18n.tr("Cancel")
                onClicked: panel.rootPwClose()
            }
            TextButton {
                Layout.alignment: Qt.AlignBottom
                text: Firewall.unlockBusy ? I18n.tr("Checking…") : I18n.tr("Allow")
                primary: true
                onClicked: panel.rootUnlock()
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

    // ── Headline numbers ────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8
        Repeater {
            model: [
                { label: I18n.tr("Connected"), value: Firewall.inbound.filter(e => e.state !== "authenticating").length, color: Theme.accent },
                { label: I18n.tr("Scans 24h"), value: FwActivity.events.filter(e => e.kind === "scan").length,
                  color: FwActivity.events.some(e => e.kind === "scan") ? Theme.red : Theme.fg },
                { label: I18n.tr("Blocked 24h"), value: Firewall.blocked.length, color: Theme.fg }
            ]
            Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: statCol.implicitHeight + Theme.dp(20)
                radius: Theme.dp(14)
                color: Theme.surface
                Column {
                    id: statCol
                    anchors.centerIn: parent
                    spacing: Theme.dp(2)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.value
                        color: modelData.color
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.dp(22)
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }
        }
    }

    // ── Activity: everything other machines did to this PC (FwActivity) ─────
    AiCard {
        id: activity
        Layout.fillHeight: false
        property string filter: "all"
        property bool expanded: false
        readonly property var items: FwActivity.events.filter(e => filter === "all" || FwActivity.group(e.kind) === filter)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(8)
            AiCardTitle {
                Layout.fillWidth: true
                text: I18n.tr("Activity")
                badge: FwActivity.events.length > 0 ? FwActivity.events.length + " · 24h" : ""
                badgeColor: Theme.fgDim
                Text { anchors.centerIn: parent; text: "\u{f02da}"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.dp(18) }
            }
            TextButton {
                visible: FwActivity.events.length > 0
                text: "\u{f0b5c}  " + I18n.tr("Clear")
                implicitHeight: Theme.dp(26)
                onClicked: FwActivity.clear()
            }
        }
        // Filtros
        Flow {
            Layout.fillWidth: true
            spacing: Theme.dp(6)
            Repeater {
                model: [
                    { id: "all", label: I18n.tr("All") },
                    { id: "ping", label: I18n.tr("Ping") },
                    { id: "ssh", label: "SSH" },
                    { id: "connect", label: I18n.tr("Connections") },
                    { id: "scan", label: I18n.tr("Scans") },
                    { id: "login", label: I18n.tr("Logins") },
                    { id: "brute", label: I18n.tr("Brute force") },
                    { id: "rootlock", label: I18n.tr("Root lock") },
                    { id: "blocked", label: I18n.tr("Blocked") }
                ]
                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool sel: activity.filter === modelData.id
                    readonly property int count: modelData.id === "all" ? FwActivity.events.length
                        : FwActivity.events.filter(e => FwActivity.group(e.kind) === modelData.id).length
                    implicitWidth: chipText.implicitWidth + Theme.dp(18)
                    implicitHeight: Theme.dp(24)
                    radius: height / 2
                    color: sel ? Theme.accent : chipMa.containsMouse ? Theme.withAlpha(Theme.fg, 0.12) : Theme.surface
                    Behavior on color { ColorAnimation { duration: Theme.animFast } }
                    Text {
                        id: chipText
                        anchors.centerIn: parent
                        text: chip.modelData.label + (chip.count > 0 ? "  " + chip.count : "")
                        color: chip.sel ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        font.bold: chip.sel
                    }
                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { activity.filter = chip.modelData.id; activity.expanded = false }
                    }
                }
            }
        }
        Text {
            visible: !FwActivity.rulesReady || !Firewall.firewallOn || activity.items.length === 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: !Firewall.firewallOn ? I18n.tr("Turn the firewall on to log who pings or connects to your PC.")
                : !FwActivity.rulesReady ? I18n.tr("Only blocked traffic is logged until the new firewall rules are installed (scripts/qs-firewall.nft).")
                : I18n.tr("Nothing yet. Pings, SSH logins, connections, scans, blocked traffic and root-lock refusals show up here.")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Repeater {
            model: activity.items.slice(0, activity.expanded ? 60 : 10)
            FwRow {
                required property var modelData
                readonly property var k: FwActivity.kinds[modelData.kind]
                dotColor: k.color
                title: k.label + " · " + modelData.who + "  ·  " + panel.ago(modelData.t / 1000)
                subtitle: modelData.where + (modelData.iface ? " · via " + modelData.iface : "")
                          + (modelData.n > 1 ? " · ×" + modelData.n : "")
                tag: modelData.service
                tagColor: k.color
                // Escaneo: lo que encontró, como lo vería nmap
                detail: {
                    const r = modelData.scan
                    if (!r) return ""
                    const lines = [I18n.tr("Found open") + ": " + (r.open.length > 0 ? FwActivity.portList(r.open, 10) : I18n.tr("none"))]
                    if (r.closed.length > 0) lines.push(I18n.tr("Closed") + ": " + FwActivity.portList(r.closed, 10))
                    lines.push(I18n.tr("Blocked") + ": " + r.filtered.length + (r.filtered.length > 0 ? " (" + FwActivity.portList(r.filtered, 8) + ")" : "")
                               + " · " + Math.max(1, Math.round((r.last - r.first) / 1000)) + " s")
                    return lines.join("\n")
                }
            }
        }
        TextButton {
            visible: activity.items.length > 10
            Layout.alignment: Qt.AlignHCenter
            text: activity.expanded ? I18n.tr("Show less") : I18n.tr("Show all") + " (" + activity.items.length + ")"
            implicitHeight: Theme.dp(26)
            onClicked: activity.expanded = !activity.expanded
        }
    }

    // ── IPs blocked from the scan alert (FwBlock), each for a while ─────────
    AiCard {
        id: blockedCard
        Layout.fillHeight: false
        visible: FwBlock.blocked.length > 0
        // Re-read when the panel opens, and tick the "min left" while open
        Component.onCompleted: FwBlock.refresh()
        property real now: Date.now()
        Timer { interval: 30000; running: blockedCard.visible; repeat: true; onTriggered: blockedCard.now = Date.now() }
        AiCardTitle {
            text: I18n.tr("Blocked IPs")
            badge: String(FwBlock.blocked.length)
            badgeColor: Theme.red
            Text { anchors.centerIn: parent; text: "\u{f0ecc}"; color: Theme.red; font.family: Theme.fontFamily; font.pixelSize: Theme.dp(18) }
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

    // ── Who is connected right now ──────────────────────────────────────────
    AiCard {
        Layout.fillHeight: false
        AiCardTitle {
            text: I18n.tr("Connected now")
            badge: Firewall.inbound.length > 0 ? String(Firewall.inbound.filter(e => e.state !== "authenticating").length) : ""
            Text { anchors.centerIn: parent; text: "\u{f0437}"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: Theme.dp(18) }
        }
        Text {
            visible: Firewall.inbound.length === 0
            text: I18n.tr("Nobody is connected to your PC.")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Repeater {
            model: Firewall.inbound
            FwRow {
                required property var modelData
                // SSH still at the password prompt: not in yet
                readonly property bool signingIn: modelData.state === "authenticating"
                dotColor: signingIn ? Theme.yellow : panel.whereColor(modelData.where)
                title: modelData.ip + (signingIn ? "  ·  " + I18n.tr("signing in…") : "")
                subtitle: (signingIn ? I18n.tr("Typing the password, not logged in yet") + " · " : "")
                          + modelData.where + " · port " + modelData.rport
                tag: modelData.service
                tagColor: Theme.accent
                // SSH logins of this user: end the session (kicks them out)
                actionText: modelData.session ? "\u{f0343}  " + I18n.tr("Disconnect") : ""
                onActionClicked: Firewall.disconnect(modelData)
            }
        }
    }

    // ── Blocked by the firewall ─────────────────────────────────────────────
    AiCard {
        Layout.fillHeight: false
        AiCardTitle {
            text: I18n.tr("Blocked")
            badge: I18n.tr("24h")
            badgeColor: Theme.fgDim
            Text { anchors.centerIn: parent; text: "\u{f0ecc}"; color: Theme.red; font.family: Theme.fontFamily; font.pixelSize: Theme.dp(18) }
        }
        Text {
            visible: Firewall.blocked.length === 0
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Firewall.firewallOn ? I18n.tr("Nothing blocked in the last 24 hours.")
                                      : I18n.tr("Turn the firewall on to block and list unknown connections.")
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Repeater {
            model: Firewall.blocked.slice(0, 10)
            FwRow {
                required property var modelData
                dotColor: panel.whereColor(modelData.where)
                title: modelData.ip + "  ·  " + panel.ago(modelData.t)
                subtitle: modelData.where + " · via " + modelData.iface
                tag: modelData.proto + " " + modelData.port
                tagColor: Theme.fgDim
            }
        }
    }

    // ── Open ports ──────────────────────────────────────────────────────────
    AiCard {
        Layout.fillHeight: false
        AiCardTitle {
            text: I18n.tr("Open ports")
            badge: Firewall.newPorts.length > 0 ? Firewall.newPorts.length + " " + I18n.tr("new")
                                                : String(Firewall.listening.length)
            badgeColor: Firewall.newPorts.length > 0 ? Theme.yellow : Theme.fgDim
            Text { anchors.centerIn: parent; text: "\u{f0208}"; color: Theme.fgDim; font.family: Theme.fontFamily; font.pixelSize: Theme.dp(18) }
        }
        // New (untrusted) ports: yellow chips, click one to trust it.
        RowLayout {
            Layout.fillWidth: true
            visible: Firewall.newPorts.length > 0
            spacing: Theme.dp(8)
            Text {
                Layout.fillWidth: true
                text: I18n.tr("New ports opened since you last checked. Trust the ones you expect.")
                color: Theme.yellow
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
            TextButton {
                text: I18n.tr("Trust all")
                onClicked: Firewall.trustAll()
            }
        }
        // Listening isn't the same as reachable: say who can actually get in
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: {
                const n = r => Firewall.listening.filter(l => l.reach === r).length
                return I18n.tr("%1 reachable from your network · %2 only for your devices or limited · %3 blocked by the firewall")
                    .arg(n("open")).arg(n("limited")).arg(n("blocked"))
            }
            color: Theme.fgMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }
        Repeater {
            // Reachable first, blocked last
            model: Firewall.listening.slice().sort((a, b) =>
                ["open", "limited", "blocked"].indexOf(a.reach) - ["open", "limited", "blocked"].indexOf(b.reach))
            FwRow {
                id: portRow
                required property var modelData
                readonly property bool isNew: Firewall.isNewPort(modelData)
                readonly property bool isSsh: modelData.proto === "tcp" && modelData.port === "22"
                Layout.fillWidth: true
                dotColor: isNew || modelData.reach === "open" ? Theme.yellow
                        : modelData.reach === "limited" ? Theme.green : Theme.fgDim
                title: (modelData.process || I18n.tr("Unknown")) + (isNew ? "  ·  " + I18n.tr("new") : "")
                subtitle: modelData.reach_text || ""
                detail: modelData.about || ""
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
