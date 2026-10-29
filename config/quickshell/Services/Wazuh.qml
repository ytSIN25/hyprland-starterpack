pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Controls the local Docker Compose Wazuh stack through a root-owned helper.
// The helper is installed separately and permitted through a narrow sudoers rule.
Singleton {
    id: wazuh

    property bool running: false
    property bool busy: false

    function toggle() {
        if (busy)
            return
        busy = true
        toggleProc.running = true
    }

    function refresh() {
        if (!statusProc.running)
            statusProc.running = true
    }

    Process {
        id: toggleProc
        command: ["sudo", "-n", "/usr/local/bin/quickshell-wazuh", "toggle"]

        onExited: {
            wazuh.busy = false
            refreshDelay.restart()
        }
    }

    Timer {
        id: refreshDelay
        interval: 700
        onTriggered: wazuh.refresh()
    }

    Process {
        id: statusProc
        command: ["sudo", "-n", "/usr/local/bin/quickshell-wazuh", "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim()
                if (value === "ON")
                    wazuh.running = true
                else if (value === "OFF")
                    wazuh.running = false
            }
        }
    }

    // Keep the icon synchronized with Docker even if the stack is started or
    // stopped outside the bar.
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: wazuh.refresh()
    }
}
