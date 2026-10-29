//@ pragma Env QV4_FORCE_INTERPRETER = 1
// Punto de entrada del shell: una barra por monitor.
// Se fuerza el intérprete de QV4 para evitar una caída reproducida del JIT de
// Qt 6.11.1 (QV4::Value::sameValueZero) al reevaluar bindings de larga vida.
// La bandeja usa su propio menú QML, así que no necesita QApplication/Widgets.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Background
import qs.Bar
import qs.Config
import qs.Desktop
import qs.Modules.Carousel
import qs.Panels
import qs.Services

ShellRoot {
    id: shell

    // Un único inhibidor global para el modo cafeína. Hypridle respeta los
    // inhibidores systemd de tipo "idle", por lo que pausa todos sus listeners
    // (brillo, bloqueo, DPMS y suspensión). Al poner running a false, Process
    // envía SIGTERM y systemd-inhibit libera el bloqueo inmediatamente.
    Process {
        id: caffeineInhibitor
        running: Settings.caffeine
        // setpriv --pdeathsig: si Quickshell muere o se reinicia (pkill,
        // Super+R), el inhibidor recibe SIGTERM y no queda huérfano
        // bloqueando el salvapantallas con la cafeína ya apagada.
        command: [
            "setpriv", "--pdeathsig", "TERM",
            "systemd-inhibit",
            "--what=idle",
            "--who=Quickshell",
            "--why=Caffeine mode active",
            "--mode=block",
            "sleep", "infinity"
        ]

        stderr: SplitParser {
            onRead: (line) => console.warn("Caffeine: " + line)
        }

        onExited: (exitCode, exitStatus) => {
            // Si el comando falla mientras debía estar activo, no dejamos la
            // interfaz mostrando un estado que en realidad no está protegido.
            if (Settings.caffeine) {
                console.warn("Caffeine: the inhibitor exited (code " + exitCode + ")")
                Settings.caffeine = false
            }
        }
    }

    readonly property int startupScreenCount: Math.max(1, Quickshell.screens.length)
    property int startupBackdropReadyCount: 0
    property int startupBarReadyCount: 0
    property bool startupCarouselReady: false
    property bool startupWallpaperScanSeen: Wallpaper.scanning
    property bool startupWallpaperReady: false

    readonly property real startupLoadProgress: Math.min(1,
        0.08
        + (Settings._loaded ? 0.16 : 0)
        + (startupWallpaperReady ? 0.18 : 0)
        + Math.min(1, startupBackdropReadyCount / startupScreenCount) * 0.22
        + (startupCarouselReady ? 0.08 : 0)
        + Math.min(1, startupBarReadyCount / startupScreenCount) * 0.28)
    readonly property bool startupLoadReady: startupLoadProgress >= 0.995

    function updateStartupWallpaperReady() {
        if (Wallpaper.scanning) {
            startupWallpaperScanSeen = true
            startupWallpaperReady = false
            return
        }
        if (startupWallpaperScanSeen || Wallpaper.list.length > 0)
            startupWallpaperReady = true
    }

    Connections {
        target: Wallpaper
        function onScanningChanged() { shell.updateStartupWallpaperReady() }
        function onListChanged() { shell.updateStartupWallpaperReady() }
        function onCurrentChanged() { shell.updateStartupWallpaperReady() }
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: shell.updateStartupWallpaperReady()
    }

    // Avisos de batería baja: ahora los muestra la dynamic island
    // (Services/Island.qml), con notificación crítica al 5%.

    // Control por IPC / atajos de teclado:
    //   qs ipc call panel controlcenter | notifications | clipboard | dnd | close
    IpcHandler {
        target: "panel"
        function controlcenter(): void { Globals.toggleControlCenter() }
        function notifications(): void { Globals.toggleNotifCenter() }
        function sysmon(): void { Globals.toggleSysMon() }
        function clipboard(): void { Globals.toggleClipboard() }
        function dashboard(): void { Globals.toggleDashboard() }
        function aiusage(): void { Globals.toggleAiUsage() }
        function firewall(): void { Globals.toggleFirewall() }
        function privacy(): void { Globals.togglePrivacy() }
        function disk(): void { Globals.toggleDisk() }
        function logs(): void { Globals.toggleLogs() }
        function wifipass(): void { WifiPasswords.open ? WifiPasswords.closePanel() : WifiPasswords.openPanel() }
        function capture(): void { ScreenCapture.openToolbar(false) }
        function record(): void { ScreenCapture.openToolbar(true) }
        function settings(): void { Globals.toggleSettings() }
        function dnd(): void { Globals.dnd = !Globals.dnd }
        function caffeine(): void { Settings.caffeine = !Settings.caffeine }
        function hidden(): void { Globals.showHiddenIcons = !Globals.showHiddenIcons }
        function close(): void { Globals.closeAll() }
    }

    // Cierre automático al bloquear la sesión. Escucha la señal 'Lock' de
    // logind (la emite `loginctl lock-session`, que es lo que usa hypridle al
    // inactivarse/suspender), así los paneles se cierran solos sin depender de
    // que el lock_cmd ejecute `qs ipc`. Usa `gdbus monitor` (suscripción de
    // cliente, sin privilegios), no `dbus-monitor --system` que requiere root.
    // Cada señal sale como: ".../session/_X: org.freedesktop.login1.Session.Lock ()"
    Process {
        id: lockMonitor
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("Session.Lock") !== -1)
                    Globals.closeAll()
                // Suspensión/reanudación: por este mismo bus logind emite
                // Manager.PrepareForSleep(true) antes de dormir y (false) al
                // despertar. Lo reenviamos al coordinador central Resume, al que
                // se suscriben los servicios que necesitan recuperarse tras el
                // resume (WiFi, clima, brillo, monitor de sistema, pantallas…).
                else if (line.indexOf("PrepareForSleep") !== -1)
                    Resume.notify(line.indexOf("true") !== -1)
            }
        }
        // Si el monitor muere (reinicio de dbus, etc.) se relanza tras una pausa.
        onExited: lockRestart.restart()
    }
    Timer {
        id: lockRestart
        interval: 3000
        onTriggered: lockMonitor.running = true
    }

    // Los popups de notificación animan su entrada/salida DESDE QML; sin esta
    // regla Hyprland superpone además su animación de layers (fade al mapear/
    // desmapear y el redimensionado de la capa), lo que producía una entrada
    // doble "forzada" y una franja gris residual al desvanecer la instantánea
    // del último búfer tras cerrar.
    function applyLayerRules() {
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "qs-noanim-popups", match = '
            + '{ namespace = "qs-popups" }, no_anim = true })'])
    }
    // Terminal y AppTemplates son singletons perezosos: sin tocarlos al
    // arrancar no existen hasta abrir Ajustes, y kitty/starship no seguían
    // al tema dinámico al cambiar de fondo.
    Component.onCompleted: {
        applyLayerRules()
        Terminal.apply()
        AppTemplates.scheduleApplyAll()
    }
    // Fondo de pantalla: eliminado -- el módulo qs.Background/Backdrop no
    // existe en esta instalación, así que se quitó el import y este bloque
    // en vez de dejar el shell sin arrancar. startupBackdropReadyCount se
    // queda en 0 (nunca se incrementa); es inofensivo, solo resta algo de
    // "peso" al cálculo de progreso del splash de arranque más abajo.

    // Fondo animado: solo existe mientras el fondo actual es un vídeo.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: videoSlot
            required property var modelData
            active: Wallpaper.currentIsVideo
            VideoWall { modelData: videoSlot.modelData }
        }
    }

    // Plugin autocontenido: carrusel para elegir fondo (Super+W → IPC
    // "carousel"). No modifica ningún componente; solo se instancia aquí.
    WallpaperCarousel {
        Component.onCompleted: shell.startupCarouselReady = true
    }

    // Splash breve al entrar en la sesión; tapa el salto visual entre TTY y
    // escritorio mientras aparecen la barra y el fondo. Se usa solo al arrancar:
    // tras la animación se libera (active=false) para no dejar una ventana por
    // monitor residente toda la sesión.


    // Reloj de escritorio (qs/Desktop/DesktopClock.qml): ventana layer-shell en
    // la capa Bottom — por encima del fondo de pantalla y por debajo de las
    // ventanas normales, con máscara vacía para dejar pasar los clics.
    // Para tenerlo solo en el monitor principal, sustituir este bloque por un
    // simple `DesktopClock {}`.
    Variants {
        model: Quickshell.screens
        delegate: DesktopClock {}
    }

    // Una instancia de Bar por pantalla conectada.
    Variants {
        model: Quickshell.screens
        delegate: Bar {
            Component.onCompleted: shell.startupBarReadyCount++
        }
    }

    // Notch central (hora; se despliega con reproductor y semana al pasar el ratón).
    Variants {
        model: Quickshell.screens
        delegate: Notch {}
    }

    // Ranura de panel con cierre animado: se construye al abrir ('open') y se
    // libera cuando termina la animación de cierre — 'closing' mantiene el
    // loader activo mientras la ventana siga visible (openProgress > 0), así
    // el cierre anima completo antes de destruir. Toda la maquinaria vive
    // aquí; cada uso declara solo su bandera 'open' y el panel que aloja.
    component PanelSlot: LazyLoader {
        property bool open: false
        property bool closing: false
        activeAsync: open || closing
    }

    // Paneles emergentes (Globals controla su visibilidad desde los widgets
    // de la barra). Un único recorrido de pantallas aloja las seis ranuras de
    // cada monitor; Popout anima al nacer vía Component.onCompleted.
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: scr
            required property var modelData

            // Solo el monitor donde se abrió el panel construye su ranura: los
            // demás ni instancian (antes se creaban N copias del panel, N-1
            // invisibles, con sus timers y decodificaciones duplicados). Con
            // openedOnMonitor vacío (sin Hyprland) instancian todos, como antes.
            readonly property bool showsPanels: Globals.openedOnMonitor === ""
                                                || scr.modelData.name === Globals.openedOnMonitor

            PanelSlot {
                id: ccS
                open: Globals.controlCenterOpen && scr.showsPanels
                ControlCenter { modelData: scr.modelData; onVisibleChanged: ccS.closing = visible }
            }
            PanelSlot {
                id: ncS
                open: Globals.notifCenterOpen && scr.showsPanels
                NotificationCenter { modelData: scr.modelData; onVisibleChanged: ncS.closing = visible }
            }
            PanelSlot {
                id: smS
                open: Globals.sysMonOpen && scr.showsPanels
                SystemMonitor { modelData: scr.modelData; onVisibleChanged: smS.closing = visible }
            }
            PanelSlot {
                id: clipS
                open: Globals.clipboardOpen && scr.showsPanels
                ClipboardPanel { modelData: scr.modelData; onVisibleChanged: clipS.closing = visible }
            }
            PanelSlot {
                id: dashS
                open: Globals.dashboardOpen && scr.showsPanels
                Dashboard { modelData: scr.modelData; onVisibleChanged: dashS.closing = visible }
            }
            PanelSlot {
                id: gpuS
                open: Globals.gpuOffloadOpen && scr.showsPanels
                GpuOffloadPanel { modelData: scr.modelData; onVisibleChanged: gpuS.closing = visible }
            }
            PanelSlot {
                id: updS
                open: Globals.updatesOpen && scr.showsPanels
                UpdatesPanel { modelData: scr.modelData; onVisibleChanged: updS.closing = visible }
            }
            PanelSlot {
                id: aiUsageS
                open: Globals.aiUsageOpen && scr.showsPanels
                AiUsagePanel { modelData: scr.modelData; onVisibleChanged: aiUsageS.closing = visible }
            }
            PanelSlot {
                id: firewallS
                open: Globals.firewallOpen && scr.showsPanels
                FirewallPanel { modelData: scr.modelData; onVisibleChanged: firewallS.closing = visible }
            }
            PanelSlot {
                id: privacyS
                open: Globals.privacyOpen && scr.showsPanels
                PrivacyPanel { modelData: scr.modelData; onVisibleChanged: privacyS.closing = visible }
            }
            PanelSlot {
                id: diskS
                open: Globals.diskOpen && scr.showsPanels
                DiskCleanPanel { modelData: scr.modelData; onVisibleChanged: diskS.closing = visible }
            }
            PanelSlot {
                id: logsS
                open: Globals.logsOpen && scr.showsPanels
                LogsPanel { modelData: scr.modelData; onVisibleChanged: logsS.closing = visible }
            }
            PanelSlot {
                id: batteryS
                open: Globals.batteryOpen && scr.showsPanels
                BatteryDetail { modelData: scr.modelData; onVisibleChanged: batteryS.closing = visible }
            }
        }
    }

    // La toolbar de captura es única (no por pantalla): la píldora basta para
    // controlar la grabación y ScreenCapture (singleton) conserva el estado.
    // Si se reabre mientras graba, se reconstruye al momento.
    PanelSlot {
        id: sctS
        open: Globals.screenCaptureOpen
        ScreenCaptureToolbar { onVisibleChanged: sctS.closing = visible }
    }

    // La píldora de grabación solo existe mientras se graba, y solo con la
    // barra vertical: con la horizontal la grabación vive en la dynamic island.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: pillL
            required property var modelData
            active: ScreenCapture.isRecording && Theme.barVertical
            RecordingPill { modelData: pillL.modelData }
        }
    }
    // Ventana de ajustes: una sola ventana real (toplevel de Hyprland). Carga
    // perezosa: no se construye hasta el primer uso y se libera al cerrarla.
    LazyLoader {
        active: Globals.settingsOpen
        Settings {}
    }
    // Modales de red: casos raros, se construyen solo al abrirse y se liberan al
    // cerrar.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: wifiL
            required property var modelData
            active: Net.promptNetwork !== null
            WifiPasswordModal { modelData: wifiL.modelData }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: ipL
            required property var modelData
            active: Net.ipConfigOpen
            IpSettingsModal { modelData: ipL.modelData }
        }
    }
    // Modal de "monitorizar una IP" (botón de la barra, PingMonitor): mismo
    // patrón que el de red -- solo se construye al abrirse.
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: pingL
            required property var modelData
            active: PingMonitor.open
            PingIpModal { modelData: pingL.modelData }
        }
    }
    // Modal de contraseñas WiFi guardadas (WifiPasswords).
    Variants {
        model: Quickshell.screens
        delegate: LazyLoader {
            id: wifiPassL
            required property var modelData
            active: WifiPasswords.open
            WifiPassModal { modelData: wifiPassL.modelData }
        }
    }
    // Con la barra horizontal el volumen/brillo los muestra la dynamic island
    // (Bar/Notch.qml); el OSD clásico solo queda para la barra vertical, donde
    // el notch se oculta.
    Variants {
        model: Theme.barVertical ? Quickshell.screens : []
        delegate: VolumeOSD {}
    }
    Variants {
        model: Quickshell.screens
        delegate: NotificationPopups {}
    }
}
