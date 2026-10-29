pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Historial de arranques para el panel de logs (Panels/LogsPanel.qml):
// scripts/crash-report.py dice cómo acabó cada sesión (normal, botón de
// encendido, corte/cuelgue) y qué falló (apps, memoria, kernel/GPU).
// Al arrancar, si la sesión anterior no terminó bien y aún no se ha visto,
// emite unexpected() → aviso en la isla.
Singleton {
    id: root

    signal unexpected(var boot)

    property var boots: []
    property bool loading: false
    readonly property var last: boots.length > 1 ? boots[1] : null   // sesión anterior
    // Sesiones raras sin revisar (para el punto rojo del botón).
    property string ackedId: ""
    readonly property bool hasUnseen: last !== null && (last.status === "power" || last.status === "crash")
                                      && last.id !== ackedId

    function refresh() {
        if (proc.running) return
        root.loading = true
        proc.running = true
    }
    function ack() {
        if (!last) return
        root.ackedId = last.id
        ackFile.setText(last.id)
    }
    // Abre el log completo (o solo errores) de un arranque en una terminal.
    function openLog(index, errorsOnly) {
        const args = ["journalctl", "-b", String(index), "-e", "--no-hostname"]
        if (errorsOnly) args.push("-p", "err")
        Quickshell.execDetached(["kitty", "--title", "Logs", "-e"].concat(args))
    }

    Process {
        id: proc
        command: ["python3", "-I", decodeURIComponent(Qt.resolvedUrl("../scripts/crash-report.py")
                                                     .toString().replace(/^file:\/\//, "")), "8"]
        stdout: StdioCollector {
            onStreamFinished: {
                let b = []
                try { b = JSON.parse(this.text || "[]") } catch (e) { console.warn("CrashLog: " + e) }
                const first = !root._checked
                root.boots = b
                root.loading = false
                root._checked = true
                if (first && root.hasUnseen) root.unexpected(root.last)
            }
        }
        onExited: root.loading = false
    }
    property bool _checked: false

    FileView {
        id: ackFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/logs-ack"
        printErrors: false
        onLoaded: { root.ackedId = text().trim(); startCheck.start() }
        onLoadFailed: startCheck.start()
    }
    // Al arrancar (con margen para que la isla esté lista).
    Timer {
        id: startCheck
        interval: 5000
        onTriggered: root.refresh()
    }
}
