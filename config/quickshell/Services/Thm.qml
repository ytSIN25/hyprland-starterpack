pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Perfil público de TryHackMe (streak, capability score). Endpoint sin
// autenticación -- confirmado con una petición limpia, sin cookies, desde
// fuera del navegador: misma respuesta que con sesión iniciada. Si TryHackMe
// cambia esta API alguna vez, esto se queda en silencio con los últimos
// valores conocidos en vez de romper el panel entero.
Singleton {
    id: thm

    // Cambiar aquí si algún día se quiere para otro usuario.
    property string username: "chrysanderpui"

    property int streak: -1          // -1 = aún sin dato/fallo, no "0 días"
    property real capability: -1     // idem
    property string leagueTier: ""

    function refresh() {
        if (!profileProc.running) profileProc.running = true
    }

    Process {
        id: profileProc
        command: ["curl", "-s", "--max-time", "6",
                   "-A", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36",
                  "https://tryhackme.com/api/v2/public-profile?username=" + thm.username]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const res = JSON.parse(this.text)
                    const d = res && res.data
                    if (!d) return
                    if (typeof d.streak === "number") thm.streak = d.streak
                    if (d.capabilityScore && typeof d.capabilityScore.value === "number")
                        thm.capability = d.capabilityScore.value
                    if (typeof d.leagueTier === "string") thm.leagueTier = d.leagueTier
                } catch (e) {
                    // JSON inválido (página de error, timeout de curl con
                    // salida vacía, etc.) -- se ignora, quedan los últimos
                    // valores buenos conocidos en vez de romper el panel.
                }
            }
        }
    }

    // El streak/capability no cambian con frecuencia -- no hace falta (ni
    // es amable) pegarle a este endpoint más que cada rato largo.
    Timer {
        interval: 20 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: thm.refresh()
    }
}
