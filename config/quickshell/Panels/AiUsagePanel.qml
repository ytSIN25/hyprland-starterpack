import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Services

// AI usage dashboard: Claude/Codex plan limits, local API-equivalent
// spending, last activity and a daily trend. Data: Services/AiUsage.qml.
Popout {
    id: panel
    ns: "qs-ai-usage"
    cardWidth: 560
    cardMinWidth: 420
    scrollable: false
    shown: Globals.aiUsageOpen

    onShownChanged: if (shown) { panel.now = Date.now(); periodMenu.open = false; AiUsage.refresh(false) }

    // Brand colors: identity of each provider, not status.
    readonly property color claudeColor: "#d97757"
    readonly property color codexColor: "#7b8ff7"

    // Period for Spending + Trend: 1 = today, 7 or 30 days.
    property int periodDays: 1
    readonly property var periods: [
        { "days": 1, "label": I18n.tr("Today") },
        { "days": 7, "label": I18n.tr("7 days") },
        { "days": 30, "label": I18n.tr("30 days") }
    ]
    function periodLabel(d) {
        for (let i = 0; i < periods.length; i++)
            if (periods[i].days === d) return periods[i].label
        return ""
    }

    // Ticks while open so countdowns, pace markers and "x ago" stay current.
    property real now: Date.now()
    Timer {
        interval: 30 * 1000
        running: panel.shown
        repeat: true
        onTriggered: panel.now = Date.now()
    }

    // ── Formatting ───────────────────────────────────────────────────────────
    function shortDuration(ms) {
        const mins = Math.max(0, Math.round(ms / 60000))
        const d = Math.floor(mins / 1440), h = Math.floor((mins % 1440) / 60), m = mins % 60
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }
    function windowLabel(secs, fallback) {
        if (!secs) return fallback
        if (secs <= 5 * 3600) return I18n.tr("Session")
        if (secs === 7 * 86400) return I18n.tr("Week")
        return Math.round(secs / 86400) + "d"
    }
    function money(v) { return "$" + (v || 0).toFixed(2) }
    function tokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
        return String(n)
    }
    // Last activity → "Active" (just now), "Idle" (this hour), else "x ago".
    function activity(epoch) {
        if (!epoch) return I18n.tr("Not installed")
        const s = (panel.now / 1000) - epoch
        if (s < 120) return I18n.tr("Active")
        if (s < 3600) return I18n.tr("Idle")
        if (s < 86400) return Math.floor(s / 3600) + "h " + I18n.tr("ago")
        if (s < 14 * 86400) return Math.floor(s / 86400) + "d " + I18n.tr("ago")
        return Math.floor(s / (7 * 86400)) + " wk. " + I18n.tr("ago")
    }

    // ── Header: period dropdown + refresh ───────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space8
        z: 2

        Item {
            implicitWidth: periodRow.implicitWidth
            implicitHeight: periodRow.implicitHeight + Theme.dp(4)

            RowLayout {
                id: periodRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.dp(6)
                Text {
                    text: panel.periodLabel(panel.periodDays)
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 4
                    font.bold: true
                }
                Text {
                    text: periodMenu.open ? "\u{f0143}" : "\u{f0140}"   // chevron up / down
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: periodMenu.open = !periodMenu.open
            }

            // Dropdown, floating over the cards below.
            Rectangle {
                id: periodMenu
                property bool open: false
                visible: open
                y: parent.height + Theme.dp(6)
                width: Theme.dp(140)
                height: menuCol.implicitHeight + Theme.dp(8)
                radius: Theme.dp(12)
                color: Theme.surfaceHi
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.overlay, 0.5)

                Column {
                    id: menuCol
                    anchors.fill: parent
                    anchors.margins: Theme.dp(4)
                    Repeater {
                        model: panel.periods
                        Rectangle {
                            required property var modelData
                            width: menuCol.width
                            height: Theme.dp(30)
                            radius: Theme.dp(8)
                            color: optMa.containsMouse ? Theme.withAlpha(Theme.accent, 0.16) : "transparent"
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.dp(10)
                                text: modelData.label
                                color: modelData.days === panel.periodDays ? Theme.accent : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: modelData.days === panel.periodDays
                            }
                            MouseArea {
                                id: optMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { panel.periodDays = modelData.days; periodMenu.open = false }
                            }
                        }
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }

        Text {
            id: spinner
            visible: AiUsage.loading
            text: "󰑮"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 1000
                loops: Animation.Infinite
                running: spinner.visible
            }
        }

        IconButton {
            icon: "󰑐"
            iconColor: Theme.fgMuted
            hoverIconColor: Theme.accent
            hoverColor: Theme.withAlpha(Theme.accent, 0.16)
            enabled: !AiUsage.loading
            onClicked: AiUsage.refresh(true)
        }
    }

    // ── Cards ────────────────────────────────────────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Theme.dp(12)
        rowSpacing: Theme.dp(12)

        // Claude
        AiCard {
            readonly property var info: AiUsage.claude
            readonly property bool ok: !!(info && info.ok)

            AiCardTitle {
                text: "Claude"
                badge: parent.parent.ok ? parent.parent.info.plan : ""
                badgeColor: panel.claudeColor
                ClaudeMark { anchors.centerIn: parent; color: panel.claudeColor }
            }
            Text {
                Layout.fillWidth: true
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                wrapMode: Text.WordWrap
                visible: !parent.parent.ok
                text: (parent.parent.info && parent.parent.info.error) ? parent.parent.info.error : I18n.tr("loading…")
            }
            AiMeter {
                now: panel.now
                visible: parent.parent.ok
                label: panel.windowLabel(visible ? parent.parent.info.five_hour_window : 0, I18n.tr("Session"))
                pct: visible ? parent.parent.info.five_hour : 0
                resetEpoch: visible ? parent.parent.info.five_hour_reset : null
                windowSecs: visible ? parent.parent.info.five_hour_window : null
                barColor: panel.claudeColor
            }
            AiMeter {
                now: panel.now
                visible: parent.parent.ok && parent.parent.info.seven_day !== null
                label: panel.windowLabel(visible ? parent.parent.info.seven_day_window : 0, I18n.tr("Week"))
                pct: visible ? parent.parent.info.seven_day : 0
                resetEpoch: visible ? parent.parent.info.seven_day_reset : null
                windowSecs: visible ? parent.parent.info.seven_day_window : null
                barColor: panel.claudeColor
            }
            // Per-model weekly caps (Opus / Sonnet), only on plans that have them.
            Repeater {
                model: (parent.parent.ok && parent.parent.info.extra) ? parent.parent.info.extra : []
                delegate: AiMeter {
                now: panel.now
                    required property var modelData
                    label: modelData.label
                    pct: modelData.pct
                    resetEpoch: modelData.reset
                    windowSecs: 7 * 86400
                    barColor: panel.claudeColor
                }
            }
            Item { Layout.fillHeight: true }
        }

        // Codex
        AiCard {
            readonly property var info: AiUsage.codex
            readonly property bool ok: !!(info && info.ok)

            AiCardTitle {
                text: "Codex"
                badge: parent.parent.ok ? parent.parent.info.plan : ""
                badgeColor: panel.codexColor
                CodexMark { anchors.centerIn: parent; color: panel.codexColor }
            }
            Text {
                Layout.fillWidth: true
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                wrapMode: Text.WordWrap
                visible: !parent.parent.ok
                text: (parent.parent.info && parent.parent.info.error) ? parent.parent.info.error : I18n.tr("loading…")
            }
            AiMeter {
                now: panel.now
                visible: parent.parent.ok
                label: panel.windowLabel(visible ? parent.parent.info.five_hour_window : 0, I18n.tr("Session"))
                pct: visible ? parent.parent.info.five_hour : 0
                resetEpoch: visible ? parent.parent.info.five_hour_reset : null
                windowSecs: visible ? parent.parent.info.five_hour_window : null
                barColor: panel.codexColor
            }
            AiMeter {
                now: panel.now
                visible: parent.parent.ok && parent.parent.info.seven_day !== null
                label: panel.windowLabel(visible ? parent.parent.info.seven_day_window : 0, I18n.tr("Week"))
                pct: visible ? parent.parent.info.seven_day : 0
                resetEpoch: visible ? parent.parent.info.seven_day_reset : null
                windowSecs: visible ? parent.parent.info.seven_day_window : null
                barColor: panel.codexColor
            }
            Item { Layout.fillHeight: true }
        }

        // Spending (API-equivalent value of local Claude Code usage)
        AiCard {
            id: spendCard
            readonly property var total: AiUsage.spendTotal(panel.periodDays)
            readonly property real month: AiUsage.spendTotal(30).cost

            AiCardTitle {
                text: I18n.tr("Spending")
                Rectangle {
                    anchors.centerIn: parent
                    width: Theme.dp(18); height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: Theme.dp(1.5)
                    border.color: Theme.fgMuted
                    Text {
                        anchors.centerIn: parent
                        text: "$"
                        color: Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.dp(11)
                        font.bold: true
                    }
                }
            }
            RowLayout {
                spacing: Theme.dp(10)
                Text {
                    text: AiUsage.priced ? panel.money(spendCard.total.cost) : "—"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(34)
                    font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: Theme.dp(6)
                    text: I18n.tr("API value")
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
            // Share of the last 30 days spent in the selected period.
            Rectangle {
                id: spendTrack
                Layout.fillWidth: true
                implicitHeight: Theme.dp(6)
                radius: height / 2
                color: Theme.withAlpha(Theme.overlay, 0.35)
                Rectangle {
                    height: parent.height
                    width: spendCard.month > 0 ? Math.max(height, parent.width * spendCard.total.cost / spendCard.month) : 0
                    radius: height / 2
                    color: panel.claudeColor
                    Behavior on width { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                text: panel.tokens(spendCard.total.tokens) + " " + I18n.tr("tokens")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            Item { Layout.fillHeight: true }
        }

        // Now: last activity per tool
        AiCard {
            AiCardTitle {
                text: I18n.tr("Now")
                Text {
                    anchors.centerIn: parent
                    text: "\uf21e"   // nf-fa-heartbeat
                    color: Theme.fgMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.dp(16)
                }
            }
            Repeater {
                model: [
                    { "name": "Claude", "last": AiUsage.claudeLast, "codex": false },
                    { "name": "Codex", "last": AiUsage.codexLast, "codex": true }
                ]
                RowLayout {
                    required property var modelData
                    readonly property string actState: panel.activity(modelData.last)
                    Layout.fillWidth: true
                    spacing: Theme.dp(10)
                    Item {
                        implicitWidth: Theme.dp(18); implicitHeight: Theme.dp(18)
                        ClaudeMark { visible: !modelData.codex; anchors.centerIn: parent; size: Theme.dp(15); color: panel.claudeColor }
                        CodexMark { visible: modelData.codex; anchors.centerIn: parent; size: Theme.dp(15); color: panel.codexColor }
                    }
                    Text {
                        text: modelData.name
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    // Status dot + word: state is never carried by color alone.
                    Rectangle {
                        visible: parent.actState === I18n.tr("Active")
                        width: Theme.dp(7); height: width; radius: width / 2
                        color: Theme.green
                    }
                    Text {
                        text: parent.actState
                        color: parent.actState === I18n.tr("Active") ? Theme.fg : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    // ── Trend: daily API value, single series ───────────────────────────────
    AiCard {
        id: trend
        Layout.fillHeight: false
        // Today → the last week for context; otherwise the selected period.
        readonly property var days: AiUsage.spendDays.slice(panel.periodDays === 30 ? -30 : -7)
        readonly property real maxCost: {
            let m = 0
            for (let i = 0; i < days.length; i++) m = Math.max(m, days[i].cost || 0)
            return m
        }
        property int hovered: -1

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.dp(10)
            Text {
                text: "\uf080"   // nf-fa-bar_chart
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.dp(16)
            }
            Text {
                text: I18n.tr("Trend")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
                text: panel.periodLabel(panel.periodDays) + " · "
                      + (AiUsage.priced ? panel.money(AiUsage.spendTotal(panel.periodDays).cost) : "—")
                color: Theme.fgMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        Item {
            id: plot
            Layout.fillWidth: true
            implicitHeight: Theme.dp(96)
            readonly property real gap: Theme.dp(2)
            readonly property real labelH: Theme.dp(16)
            readonly property real chartH: height - labelH - Theme.dp(4)
            readonly property real barW: trend.days.length > 0
                ? (width - gap * (trend.days.length - 1)) / trend.days.length : 0

            // Baseline (recessive).
            Rectangle {
                y: plot.chartH
                width: parent.width; height: Theme.hairline
                color: Theme.withAlpha(Theme.overlay, 0.6)
            }

            Repeater {
                model: trend.days
                Item {
                    required property var modelData
                    required property int index
                    readonly property bool isToday: index === trend.days.length - 1
                    x: index * (plot.barW + plot.gap)
                    width: plot.barW
                    height: plot.height

                    Rectangle {
                        readonly property real h: trend.maxCost > 0 && (modelData.cost || 0) > 0
                            ? Math.max(Theme.dp(3), plot.chartH * modelData.cost / trend.maxCost) : 0
                        y: plot.chartH - h
                        width: parent.width
                        height: h
                        topLeftRadius: Math.min(Theme.dp(4), width / 2)
                        topRightRadius: topLeftRadius
                        color: panel.claudeColor
                        opacity: parent.isToday || trend.hovered === index ? 1 : 0.55
                        Behavior on height { NumberAnimation { duration: Theme.animNormal; easing.type: Easing.OutCubic } }
                    }

                    // Weekday initials for 7 bars; first/last dates for 30.
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        visible: trend.days.length <= 7 || index === 0 || parent.isToday
                        text: {
                            const d = new Date(modelData.date + "T00:00:00")
                            return trend.days.length <= 7 ? Qt.formatDate(d, "ddd").charAt(0)
                                                          : Qt.formatDate(d, "d MMM")
                        }
                        color: parent.isToday ? Theme.fg : Theme.fgMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    // Hit target: the whole column, not just the bar.
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: trend.hovered = containsMouse ? index : (trend.hovered === index ? -1 : trend.hovered)
                    }
                }
            }

            // Tooltip for the hovered bar.
            Rectangle {
                readonly property var day: trend.hovered >= 0 ? trend.days[trend.hovered] : null
                visible: day !== null
                z: 3
                width: tipText.implicitWidth + Theme.dp(16)
                height: tipText.implicitHeight + Theme.dp(10)
                radius: Theme.dp(8)
                color: Theme.surfaceHi
                border.width: Theme.hairline
                border.color: Theme.withAlpha(Theme.overlay, 0.6)
                x: Math.max(0, Math.min(plot.width - width,
                    trend.hovered * (plot.barW + plot.gap) + plot.barW / 2 - width / 2))
                y: 0
                Text {
                    id: tipText
                    anchors.centerIn: parent
                    text: parent.day
                        ? Qt.formatDate(new Date(parent.day.date + "T00:00:00"), "ddd d MMM") + "  ·  "
                          + (AiUsage.priced ? panel.money(parent.day.cost) : "—") + "  ·  "
                          + panel.tokens(parent.day.tokens) + " " + I18n.tr("tokens")
                        : ""
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }
}
