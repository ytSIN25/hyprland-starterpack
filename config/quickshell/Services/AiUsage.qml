pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Runs ~/.local/bin/ai-usage.sh and exposes Claude + Codex rate-limit usage,
// plus ~/.local/bin/ai-spend.sh for local API-equivalent spending.
// Same shape as PackageUpdates.qml: a Process kicked off by refresh(),
// parsed on stdout finish, polled on a Timer.
Singleton {
    id: au

    property bool loading: true
    // Each is either null (not fetched yet) or:
    // { ok: true, five_hour, five_hour_reset, seven_day, seven_day_reset, plan }
    // { ok: false, error }
    property var claude: null
    property var codex: null

    // From ai-spend.sh: 30 days of { date, cost (null if unpriced), tokens },
    // oldest first, and the last local activity (epoch s) per tool.
    property var spendDays: []
    property bool priced: false
    property var claudeLast: null
    property var codexLast: null

    // Only real session windows (≤ 5 h) count: some plans report a longer
    // limit (e.g. Codex's 30-day one) in the five_hour field.
    function _sessionPct(info) {
        if (!info || !info.ok || info.five_hour === null || info.five_hour === undefined) return null
        const w = info.five_hour_window
        return !w || w <= 5 * 3600 ? info.five_hour : null
    }
    readonly property int worstPct: {
        const vals = [_sessionPct(claude), _sessionPct(codex)].filter(v => v !== null)
        return vals.length ? Math.max(...vals) : -1
    }

    function statusColor(pct) {
        if (pct < 0) return Theme.fgDim
        if (pct >= 90) return Theme.red
        if (pct >= 70) return Theme.yellow
        return Theme.green
    }

    function refresh(force) {
        loading = true
        proc.command = force
            ? ["bash", Quickshell.env("HOME") + "/.local/bin/ai-usage.sh", "--force"]
            : ["bash", Quickshell.env("HOME") + "/.local/bin/ai-usage.sh"]
        proc.running = true
        if (!spendProc.running) spendProc.running = true
    }

    // Sum of the last 'n' days (1 = today) as { cost, tokens }.
    function spendTotal(n) {
        let cost = 0, tokens = 0
        const days = spendDays.slice(-n)
        for (let i = 0; i < days.length; i++) {
            cost += days[i].cost || 0
            tokens += days[i].tokens || 0
        }
        return { cost: cost, tokens: tokens }
    }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                au.loading = false
                try {
                    const data = JSON.parse(this.text)
                    au.claude = data.claude
                    au.codex = data.codex
                } catch (e) {
                    au.claude = { ok: false, error: "bad response from ai-usage.sh" }
                    au.codex = { ok: false, error: "bad response from ai-usage.sh" }
                }
            }
        }
    }

    Process {
        id: spendProc
        command: ["bash", Quickshell.env("HOME") + "/.local/bin/ai-spend.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text)
                    au.spendDays = data.days || []
                    au.priced = !!data.priced
                    au.claudeLast = data.claude_last
                    au.codexLast = data.codex_last
                } catch (e) {
                    console.warn("AiUsage: bad response from ai-spend.sh")
                }
            }
        }
    }

    Timer {
        interval: 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: au.refresh(false)
    }
}
