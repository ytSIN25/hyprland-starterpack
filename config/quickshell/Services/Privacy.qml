pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Config

// Camera / microphone privacy indicator for PrivacyWidget / PrivacyPanel.
// Camera: processes holding /dev/video* open (scan of /proc/*/fd, only this
// user's processes are visible, which covers desktop apps).
// Microphone: PipeWire capture streams (audio, not sink, stream). Streams that
// record a sink monitor (visualizers, level meters) don't count.
Singleton {
    id: priv

    // Camera users: [{pid, name}]
    property var cameraApps: []

    // Microphone capture streams (PwNode).
    readonly property var micStreams: (Pipewire.nodes?.values ?? []).filter(n =>
        n.audio && !n.isSink && n.isStream
        && n.properties?.["stream.monitor"] !== "true"
        && n.properties?.["stream.capture.sink"] !== "true")

    PwObjectTracker {
        objects: (Pipewire.nodes?.values ?? []).filter(n => n.isStream && !n.isSink)
                     .concat(Pipewire.defaultAudioSource ? [Pipewire.defaultAudioSource] : [])
    }

    readonly property bool cameraInUse: cameraApps.length > 0
    readonly property bool micInUse: micStreams.length > 0
    readonly property bool active: cameraInUse || micInUse
    readonly property bool micMuted: Pipewire.defaultAudioSource?.audio?.muted ?? false

    function streamName(n) {
        return n?.properties?.["application.name"] || n?.properties?.["application.process.binary"]
            || n?.properties?.["node.name"] || n?.name || "?"
    }
    function streamPid(n) { return parseInt(n?.properties?.["application.process.id"] ?? "", 10) || 0 }

    function toggleMicMute() {
        const a = Pipewire.defaultAudioSource?.audio
        if (a) a.muted = !a.muted
    }
    // Last resort: ends the app (SIGTERM, lets it save and exit cleanly).
    function forceQuit(pid) {
        if (pid > 0) Quickshell.execDetached(["kill", "-TERM", String(pid)])
        camTimer.restart()
    }

    Process {
        id: camProc
        command: ["sh", "-c",
            "find /proc/[0-9]*/fd -maxdepth 1 -lname '/dev/video*' 2>/dev/null | cut -d/ -f3 | sort -u | " +
            "while read -r p; do printf '%s\\t%s\\n' \"$p\" \"$(cat /proc/$p/comm 2>/dev/null)\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const apps = (this.text || "").split("\n").filter(l => l !== "").map(l => {
                    const f = l.split("\t")
                    return { pid: parseInt(f[0], 10), name: f[1] || "?" }
                })
                // Only reassign when it changed, so bindings don't churn every poll.
                if (JSON.stringify(apps) !== JSON.stringify(priv.cameraApps)) priv.cameraApps = apps
            }
        }
    }
    Timer {
        id: camTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!camProc.running) camProc.running = true
    }
}
