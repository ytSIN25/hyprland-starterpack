import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Bar pill: "AI" label + worst-case usage % across Claude/Codex, colored
// green/yellow/red. Click opens the AiUsagePanel popout (Globals.aiUsageOpen).
// Built on Pill directly (not IconPill) so we don't have to guess a Nerd
// Font glyph codepoint — swap the Text below for an IconPill { icon: "…" }
// if you'd rather have a robot/sparkle glyph matching your other pills.
Pill {
    id: root
    interactive: true
    active: Globals.aiUsageOpen
    onClicked: Globals.toggleAiUsage()

    Text {
        text: "AI"
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }

    // Highest current-session % across Claude/Codex; hidden until data arrives.
    Text {
        visible: AiUsage.worstPct >= 0
        text: Math.round(AiUsage.worstPct) + "%"
        color: AiUsage.statusColor(AiUsage.worstPct)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }
}
