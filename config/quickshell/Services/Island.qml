pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Hyprland
import qs.Config

// Estado de la "dynamic island" (Bar/Notch.qml):
//  - osd: volumen / brillo (sustituye al VolumeOSD con la barra horizontal).
//  - alert: aviso transitorio (batería, cargador, timer, canción nueva,
//    Bluetooth, red, VPN, calendario, DND/cafeína…).
//  - temporizadores: timer (cuenta atrás) y stopwatch.
//  - IA: Claude Code / Codex trabajando (hooks → scripts/island-ai-hook.sh).
//  - calendario: avisos 10 min antes y al empezar (scripts/island-calendar.py).
// La grabación, la música y los indicadores de cámara/micro los lee el
// notch directamente de ScreenCapture, Mpris y Privacy.
//
// IPC:
//   qs ipc call island timer 5m       (también 90s, 1h30m, 1:30 o "10" = min)
//   qs ipc call island stopwatch
//   qs ipc call island pause | cancel | picker | dismiss
//   qs ipc call island alert "Título" "Valor"
//   qs ipc call island demo battery|critical|charging|done|bt|wifi|vpn|event|claude|codex|
//                           usage|refresh|permission|copy|port|updates|update|caps|
//                           usb|badusb|auth|away|disk|mem|scan|download|crash|root|logout|blocked|banned|brute|brute-local
Singleton {
    id: root

    function g(cp) { return String.fromCodePoint(cp) }
    readonly property var icons: ({
        timer: "󱎫", stopwatch: g(0xF051B), alarm: g(0xF0020),
        calendar: g(0xF00F0), bt: g(0xF00AF), headphones: g(0xF02CB),
        mouse: g(0xF037D), keyboard: g(0xF030C), phone: g(0xF011C),
        wifi: g(0xF05A9), wifiOff: g(0xF05AA), ethernet: g(0xF0200), vpn: g(0xF0582),
        brightness: g(0xF00E0), record: g(0xF044A), camera: g(0xF0100), mic: g(0xF036C),
        copy: g(0xF018F), alert: g(0xF0026), shield: g(0xF0498), pkg: g(0xF03D7),
        capslock: g(0xF0632), usb: g(0xF0553), web: g(0xF059F), lockAlert: g(0xF08EE),
        disk: g(0xF02CA), download: g(0xF01DA), memory: g(0xF035B), radar: g(0xF0437), bug: g(0xF0A2E)
    })

    // Sin avisos durante el arranque (los servicios rellenan su estado).
    property bool _ready: false
    Timer {
        interval: 3000
        running: true
        onTriggered: {
            root._netKey = root._netState()
            root._btSync(false)
            root._ready = true
            root._battCheck()
        }
    }

    // ── Avisos transitorios ─────────────────────────────────────────────────
    // { icon, iconColor, title, value, valueColor, battery (0-100 o -1),
    //   charging, art, kind }
    property var alert: null

    function show(a, ms) {
        root.alert = Object.assign({
            icon: "", iconColor: "white", title: "", value: "",
            valueColor: "white", battery: -1, charging: false, art: "", kind: ""
        }, a)
        alertTimer.interval = ms || 3500
        alertTimer.restart()
    }
    function dismiss() {
        alertTimer.stop()
        root.alert = null
    }

    Timer {
        id: alertTimer
        onTriggered: root.alert = null
    }

    function _soundPath(name) {
        return decodeURIComponent(Qt.resolvedUrl("../Assets/" + name).toString().replace(/^file:\/\//, ""))
    }
    // Campanita generada (Assets/timer-done.wav); pw-play va por PipeWire.
    function playDoneSound() {
        Quickshell.execDetached(["pw-play", _soundPath("timer-done.wav")])
    }

    // ── OSD de volumen / brillo ─────────────────────────────────────────────
    property string osdKind: ""         // "" | "volume" | "brightness"
    function showOsd(kind) {
        if (!_ready || Globals.controlCenterOpen) return
        root.osdKind = kind
        osdTimer.restart()
    }
    Timer {
        id: osdTimer
        interval: 1600
        onTriggered: root.osdKind = ""
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinkAudio: sink?.audio ?? null
    readonly property bool muted: sinkAudio?.muted ?? false
    readonly property int volume: Math.round((sinkAudio?.volume ?? 0) * 100)
    function setVolume(frac) {
        if (!sinkAudio) return
        sinkAudio.muted = false
        sinkAudio.volume = Math.max(0, Math.min(1, frac))
    }
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    Connections {
        target: root.sinkAudio
        ignoreUnknownSignals: true
        function onVolumeChanged() { root.showOsd("volume") }
        function onMutedChanged() { root.showOsd("volume") }
    }
    Connections {
        target: Brightness
        function onPercentChanged() { root.showOsd("brightness") }
    }

    // ── Temporizadores: timer / stopwatch ───────────────────────────────────
    property string kind: ""            // "" | "timer" | "stopwatch"
    readonly property bool timerActive: kind !== ""
    property int timerTotal: 0          // segundos de la cuenta atrás actual
    property int remaining: 0
    property int elapsed: 0             // stopwatch
    property real _anchor: 0            // fin (cuenta atrás) o inicio (stopwatch), epoch ms
    property bool paused: false

    // Selector (clic derecho en el notch).
    property bool pickerOpen: false
    property string pickerTab: "timer"  // "timer" | "stopwatch" | "alarm"
    onPickerOpenChanged: if (!pickerOpen) alarmEdit = null
    property int pickerMinutes: 5

    readonly property string timerText: kind === "stopwatch" ? formatDuration(elapsed) : formatDuration(remaining)
    readonly property real timerProgress: kind === "stopwatch" ? (elapsed % 60) / 60
                                        : timerTotal > 0 ? remaining / timerTotal : 0
    readonly property string timerIcon: kind === "stopwatch" ? icons.stopwatch : icons.timer
    readonly property color timerColor: paused ? Theme.fgMuted
        : kind === "stopwatch" ? Theme.cyan : Theme.orange
    readonly property string timerLabel: kind === "stopwatch" ? I18n.tr("Stopwatch") : I18n.tr("Timer")

    function _countdown(sec) {
        root.timerTotal = sec
        root.remaining = sec
        root.paused = false
        root._anchor = Date.now() + sec * 1000
        root.pickerOpen = false
    }
    function startTimer(sec) {
        if (sec <= 0) return
        root.kind = "timer"
        _countdown(sec)
    }
    function startStopwatch() {
        root.kind = "stopwatch"
        root.elapsed = 0
        root.paused = false
        root._anchor = Date.now()
        root.pickerOpen = false
    }
    function togglePause() {
        if (!timerActive) return
        if (paused) {
            root._anchor = kind === "stopwatch" ? Date.now() - elapsed * 1000
                                                : Date.now() + remaining * 1000
            root.paused = false
        } else {
            root._tick()
            root.paused = true
        }
    }
    function addTime(sec) {
        if (kind !== "timer") return
        root.timerTotal += sec
        if (paused)
            root.remaining += sec
        else {
            root._anchor += sec * 1000
            root._tick()
        }
    }
    function cancelTimer() {
        root.kind = ""
        root.timerTotal = 0
        root.remaining = 0
        root.elapsed = 0
        root.paused = false
    }

    function _tick() {
        if (!timerActive || paused) return
        if (kind === "stopwatch") {
            root.elapsed = Math.floor((Date.now() - _anchor) / 1000)
            return
        }
        const left = Math.max(0, Math.ceil((_anchor - Date.now()) / 1000))
        root.remaining = left
        if (left > 0) return
        const total = timerTotal
        cancelTimer()
        show({ icon: icons.timer, iconColor: Theme.orange, title: I18n.tr("Timer"),
               value: I18n.tr("Done"), valueColor: Theme.orange }, 8000)
        playDoneSound()
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell",
            I18n.tr("Timer finished"), formatDuration(total)])
    }

    Timer {
        interval: 250
        repeat: true
        running: root.timerActive && !root.paused
        onTriggered: root._tick()
    }

    function formatDuration(sec) {
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        const s = sec % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return (h > 0 ? h + ":" + pad(m) : pad(m)) + ":" + pad(s)
    }

    // "5m", "90s", "1h30m", "1:30" (m:s) o un número suelto (= minutos).
    function parseDuration(str) {
        str = String(str).trim().toLowerCase()
        if (/^\d+(\.\d+)?$/.test(str))
            return Math.round(parseFloat(str) * 60)
        if (/^\d+:\d{1,2}$/.test(str)) {
            const p = str.split(":")
            return parseInt(p[0]) * 60 + parseInt(p[1])
        }
        let total = 0, matched = false
        const re = /(\d+(?:\.\d+)?)\s*([hms])/g
        let m
        while ((m = re.exec(str)) !== null) {
            matched = true
            total += parseFloat(m[1]) * ({ h: 3600, m: 60, s: 1 })[m[2]]
        }
        return matched ? Math.round(total) : 0
    }

    // ── Batería ─────────────────────────────────────────────────────────────
    // Avisos al cruzar 20/10/5% descargando (se rearman al subir del 20%), y
    // al conectar el cargador. A 5% además se manda notificación crítica.
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery ? battery.isLaptopBattery : false
    readonly property int batteryPct: hasBattery ? Math.round(battery.percentage * 100) : -1
    readonly property bool charging: hasBattery
        && (battery.state === UPowerDeviceState.Charging
            || battery.state === UPowerDeviceState.FullyCharged
            || battery.state === UPowerDeviceState.PendingCharge)
    readonly property bool discharging: hasBattery && battery.state === UPowerDeviceState.Discharging

    property int _battStage: 0          // 0 ok, 1 ≤20, 2 ≤10, 3 ≤5

    onBatteryPctChanged: _battCheck()
    onDischargingChanged: { _battCheck(); root._profileManual = false }
    onChargingChanged: {
        if (_ready && charging && batteryPct >= 0)
            show({ title: I18n.tr("Charging"), value: batteryPct + "%",
                   valueColor: Theme.green, battery: batteryPct, charging: true }, 3000)
    }

    function _battCheck() {
        if (!_ready || batteryPct < 0) return
        if (!discharging) {
            if (batteryPct > 20) _battStage = 0
            return
        }
        const stage = batteryPct <= 5 ? 3 : batteryPct <= 10 ? 2 : batteryPct <= 20 ? 1 : 0
        if (stage > _battStage) {
            _battStage = stage
            show({ title: stage === 3 ? I18n.tr("Critical Battery") : I18n.tr("Low Battery"),
                   value: batteryPct + "%", valueColor: Theme.red, battery: batteryPct },
                 stage === 3 ? 8000 : 5000)
            if (stage === 3)
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell",
                    I18n.tr("Critical battery"),
                    I18n.tr("%1% remaining — plug in now").arg(batteryPct)])
        } else if (stage < _battStage) {
            _battStage = stage
        }
    }

    // ── Reproductor: aviso breve al cambiar de canción ──────────────────────
    readonly property var _player: {
        const ps = Mpris.players?.values ?? []
        for (let i = 0; i < ps.length; i++)
            if (ps[i].isPlaying) return ps[i]
        return null
    }
    readonly property string _trackKey: _player
        ? (_player.trackTitle || "") + "\u0001" + (_player.trackArtist || "") : ""
    on_TrackKeyChanged: trackDebounce.restart()
    // Los metadatos llegan por partes (título, luego artista/carátula).
    Timer {
        id: trackDebounce
        interval: 400
        onTriggered: {
            const p = root._player
            if (!root._ready || !p || !(p.trackTitle || "")) return
            if (root.alert && root.alert.kind !== "media") return
            root.show({ kind: "media", icon: "󰝚", iconColor: Theme.accent,
                        title: p.trackTitle, value: p.trackArtist || "",
                        valueColor: Theme.fgMuted, art: p.trackArtUrl || "" }, 3500)
        }
    }

    // ── Bluetooth: conexión / desconexión de dispositivos ───────────────────
    property var _btKnown: ({})         // address → nombre
    Connections {
        target: BT
        function onConnectedChanged() { btDebounce.restart() }
    }
    // Espera un poco: la batería del dispositivo llega tras conectar.
    Timer {
        id: btDebounce
        interval: 1500
        onTriggered: root._btSync(root._ready)
    }
    function _btIcon(d) {
        const i = String(d?.icon || "")
        if (i.indexOf("audio") === 0) return icons.headphones
        if (i.indexOf("input-mouse") === 0) return icons.mouse
        if (i.indexOf("input-keyboard") === 0) return icons.keyboard
        if (i.indexOf("phone") === 0) return icons.phone
        return icons.bt
    }
    function _btSync(announce) {
        const now = {}
        for (const d of BT.connected) now[d.address] = d
        if (announce) {
            for (const addr in now) {
                if (root._btKnown[addr] !== undefined) continue
                const d = now[addr]
                const hasBatt = d.batteryAvailable && d.battery > 0
                const pct = Math.round(d.battery * 100)
                show({ icon: _btIcon(d), iconColor: Theme.accent, title: d.name || d.deviceName,
                       value: hasBatt ? pct + "%" : I18n.tr("Connected"),
                       valueColor: hasBatt ? (pct <= 20 ? Theme.red : Theme.green) : Theme.accent,
                       battery: hasBatt ? pct : -1 }, 3500)
            }
            for (const addr in root._btKnown)
                if (!now[addr])
                    show({ icon: icons.bt, iconColor: Theme.fgMuted, title: root._btKnown[addr],
                           value: I18n.tr("Disconnected"), valueColor: Theme.fgMuted }, 3000)
        }
        const names = {}
        for (const addr in now) names[addr] = now[addr].name || now[addr].deviceName
        root._btKnown = names
    }

    // ── Red y VPN ───────────────────────────────────────────────────────────
    property string _netKey: ""
    function _netState() {
        if (!Net.online) return "off"
        return Net.ethernet ? "eth" : "wifi:" + Net.ssid
    }
    Connections {
        target: Net
        function onOnlineChanged() { netDebounce.restart() }
        function onSsidChanged() { netDebounce.restart() }
        function onEthernetChanged() { netDebounce.restart() }
    }
    // Agrupa los cambios intermedios al saltar de una red a otra.
    Timer {
        id: netDebounce
        interval: 1200
        onTriggered: {
            const st = root._netState()
            if (!root._ready || st === root._netKey) return
            root._netKey = st
            if (st === "off")
                root.show({ icon: icons.wifiOff, iconColor: Theme.red, title: I18n.tr("Offline"),
                            value: I18n.tr("No connection"), valueColor: Theme.red }, 3500)
            else if (st === "eth")
                root.show({ icon: icons.ethernet, iconColor: Theme.green, title: I18n.tr("Ethernet"),
                            value: I18n.tr("Connected"), valueColor: Theme.green }, 3000)
            else
                root.show({ icon: icons.wifi, iconColor: Theme.green, title: Net.ssid,
                            value: I18n.tr("Connected"), valueColor: Theme.green }, 3000)
        }
    }
    Connections {
        target: Vpn
        function onConnectedChanged() {
            if (!root._ready) return
            root.show({ icon: icons.vpn, iconColor: Vpn.connected ? Theme.green : Theme.fgMuted,
                        title: "VPN", value: Vpn.connected ? I18n.tr("Connected") : I18n.tr("Disconnected"),
                        valueColor: Vpn.connected ? Theme.green : Theme.fgMuted }, 3000)
        }
    }

    // ── Calendario ──────────────────────────────────────────────────────────
    // Eventos de las próximas 24 h: [{title, start, end}] (epoch ms).
    property var events: []
    readonly property var nextEvent: {
        const now = Time.now.getTime()
        for (const e of events)
            if (e.end > now || e.start > now) return e
        return null
    }
    property var _calAlerted: ({})

    Process {
        id: calProc
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("../scripts/island-calendar.py")
                                                .toString().replace(/^file:\/\//, ""))]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.events = JSON.parse(this.text || "[]") }
                catch (e) { console.warn("Island calendar: " + e) }
            }
        }
        stderr: SplitParser { onRead: (line) => console.warn(line) }
    }
    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!calProc.running) calProc.running = true
    }
    Connections {
        target: Resume
        function onResumed() { if (!calProc.running) calProc.running = true }
    }
    Timer {
        interval: 15000
        running: root.events.length > 0
        repeat: true
        onTriggered: root._calCheck()
    }
    function _calCheck() {
        const now = Date.now()
        for (const e of events) {
            const mins = (e.start - now) / 60000
            const key = e.title + "@" + e.start
            if (mins > 0 && mins <= 10 && !_calAlerted[key + ":soon"]) {
                _calAlerted[key + ":soon"] = true
                show({ icon: icons.calendar, iconColor: Theme.accent, title: e.title,
                       value: I18n.tr("in %1 min").arg(Math.ceil(mins)), valueColor: Theme.accent }, 8000)
            } else if (mins <= 0 && mins > -2 && !_calAlerted[key + ":now"]) {
                _calAlerted[key + ":now"] = true
                show({ icon: icons.calendar, iconColor: Theme.green, title: e.title,
                       value: I18n.tr("Now"), valueColor: Theme.green }, 8000)
                playDoneSound()
            }
        }
    }

    // ── IA: Claude Code / Codex trabajando ──────────────────────────────────
    // Los hooks de ambos llaman a scripts/island-ai-hook.sh, que avisa por IPC
    // (aiEvent): UserPromptSubmit → start; Stop → stop; SessionEnd/StopFailure
    // → end; Interrupt (Codex) → interrupt; Notification de permiso (Claude) /
    // PermissionRequest (Codex) → attention; PostToolUse (Codex) → resume.
    // Sesiones activas: session id → { agent, start (epoch ms), cwd,
    // transcript, win (dirección de la ventana de Hyprland), attention (ms) }.
    property var aiSessions: ({})
    readonly property var aiList: {
        const out = []
        for (const id in aiSessions) out.push(Object.assign({ id: id }, aiSessions[id]))
        out.sort((a, b) => a.start - b.start)
        return out
    }
    readonly property bool aiActive: aiList.length > 0
    readonly property bool aiClaude: aiList.some(s => s.agent === "claude")
    readonly property bool aiCodex: aiList.some(s => s.agent === "codex")
    // Primera sesión esperando al usuario (permiso), o null.
    readonly property var aiWaiting: aiList.find(s => s.attention > 0) ?? null
    readonly property color claudeColor: "#d97757"
    readonly property color codexColor: "#7b8ff7"
    function aiColor(agent) { return agent === "codex" ? codexColor : claudeColor }
    function aiName(agent) { return agent === "codex" ? "Codex" : "Claude" }

    // Reloj de segundos solo mientras hay alguna sesión trabajando.
    property real aiNow: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: root.aiActive
        triggeredOnStart: true
        onTriggered: root.aiNow = Date.now()
    }
    function aiElapsed(s) { return Math.max(0, Math.floor((aiNow - s.start) / 1000)) }

    function _aiPatch(sid, fields) {
        if (!aiSessions[sid]) return
        const map = Object.assign({}, aiSessions)
        map[sid] = Object.assign({}, map[sid], fields)
        root.aiSessions = map
    }

    function aiEvent(agent, event, sid, cwd, transcript, win) {
        const map = Object.assign({}, aiSessions)
        if (event === "start") {
            // Un prompt nuevo en una sesión que ya trabajaba no reinicia el tiempo.
            if (!map[sid])
                map[sid] = { agent: agent, start: Date.now(), cwd: cwd || "",
                             transcript: transcript || "", win: win || "", attention: 0 }
            else
                map[sid] = Object.assign({}, map[sid], { attention: 0, win: win || map[sid].win })
            root.aiSessions = map
            return
        }
        const s = map[sid]
        if (!s) {
            // Sesión desconocida (empezó antes de arrancar el shell): aun así
            // se avisa del final, sin duración.
            if (event === "stop")
                show({ logo: agent, title: aiName(agent), value: I18n.tr("Done"),
                       valueColor: aiColor(agent), action: "focuswin:" }, 5000)
            return
        }
        if (event === "attention") {
            _aiPatch(sid, { attention: Date.now() })
            show({ logo: s.agent, title: aiName(s.agent), value: I18n.tr("Needs permission"),
                   valueColor: Theme.yellow, action: "focus:" + sid }, 10000)
            playDoneSound()
            return
        }
        if (event === "resume") {
            _aiPatch(sid, { attention: 0 })
            return
        }
        delete map[sid]
        root.aiSessions = map
        if (event === "stop")
            show({ logo: s.agent, title: aiName(s.agent),
                   value: I18n.tr("Done") + " · " + formatDuration(Math.floor((Date.now() - s.start) / 1000)),
                   valueColor: aiColor(s.agent), action: "focuswin:" + (s.win || "") }, 5000)
    }

    // ── Persistencia entre recargas ─────────────────────────────────────────
    // Quickshell recarga la config al editar cualquier .qml y el singleton
    // renace vacío: las sesiones de IA y el temporizador se guardan en
    // $XDG_RUNTIME_DIR (tmpfs, se borra al cerrar sesión) y se restauran al
    // arrancar. Las sesiones de más de 12 h se descartan.
    property bool _restored: false
    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-island-state.json"
        printErrors: false
        onLoaded: root._restore(text())
        onLoadFailed: root._restored = true
    }
    function _restore(txt) {
        let st = null
        try { st = JSON.parse(txt) } catch (e) {}
        if (st) {
            const now = Date.now()
            const map = {}
            for (const id in (st.ai || {}))
                if (now - st.ai[id].start < 12 * 3600 * 1000) map[id] = st.ai[id]
            root.aiSessions = map
            const t = st.timer
            if (t && t.kind) {
                root.kind = t.kind
                root.timerTotal = t.timerTotal
                root.remaining = t.remaining
                root.elapsed = t.elapsed
                root._anchor = t.anchor
                root.paused = t.paused
                root._tick()
            }
        }
        root._restored = true
    }
    function _save() {
        if (!_restored) return
        stateFile.setText(JSON.stringify({
            ai: aiSessions,
            timer: kind === "" ? null : { kind: kind, timerTotal: timerTotal, remaining: remaining,
                                          elapsed: elapsed, anchor: _anchor, paused: paused }
        }))
    }
    // Agrupa escrituras (el tick del timer cambia remaining 4 veces/s).
    Timer {
        id: saveDelay
        interval: 300
        onTriggered: root._save()
    }
    onAiSessionsChanged: saveDelay.restart()
    onKindChanged: saveDelay.restart()
    onPausedChanged: saveDelay.restart()
    onTimerTotalChanged: saveDelay.restart()
    on_AnchorChanged: saveDelay.restart()

    // Enfoca la terminal de la sesión (dirección guardada al empezar).
    function focusWindow(addr) {
        if (!/^0x[0-9a-f]+$/.test(addr || "")) return
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:' + addr + '" })'])
    }
    function aiFocus(sid) {
        const s = aiSessions[sid]
        if (s) focusWindow(s.win)
    }

    // Comprobación periódica de las sesiones (cada 2 s):
    //  - Ventana de la terminal cerrada (ya no está en hyprctl clients): se
    //    quita la sesión (cerrar la terminal no siempre dispara SessionEnd).
    //  - Esc no dispara Stop: si la última entrada user/assistant es el
    //    marcador exacto {"text":"[Request interrupted by user…"} (no basta con
    //    que el texto aparezca, p. ej. dentro de un fichero leído), se quita.
    //  - >30 min sin escribir el transcript: sesión caducada.
    //  - Esperando permiso: en cuanto el transcript vuelve a escribirse (se
    //    aprobó y la herramienta corrió) se quita el aviso.
    // Salida por sesión: "id\tmtime_ms\tok|interrupted|stale|gone".
    Process {
        id: aiCheck
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").filter(l => l !== "")
                if (lines.length === 0) return
                const map = Object.assign({}, root.aiSessions)
                let changed = false
                for (const l of lines) {
                    const f = l.split("\t")
                    const s = map[f[0]]
                    if (!s) continue
                    if (f[2] !== "ok") {
                        delete map[f[0]]
                        changed = true
                    } else if (s.attention > 0 && parseFloat(f[1]) > s.attention + 500) {
                        map[f[0]] = Object.assign({}, s, { attention: 0 })
                        changed = true
                    }
                }
                if (changed) root.aiSessions = map
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.aiList.some(s => s.transcript !== "" || s.win !== "")
        onTriggered: {
            if (aiCheck.running) return
            const args = []
            for (const s of root.aiList)
                if (s.transcript !== "" || s.win !== "")
                    args.push(s.id, String(Math.floor(s.start / 1000)), s.transcript || "", s.win || "")
            aiCheck.command = ["sh", "-c",
                'now=$(date +%s); ' +
                'wins=" $(hyprctl clients -j 2>/dev/null | jq -r ".[].address" 2>/dev/null | tr "\\n" " ") "; ' +
                'while [ $# -ge 4 ]; do id=$1; st=$2; f=$3; w=$4; shift 4; ' +
                'if [ -n "$w" ] && [ "$wins" != "  " ] && [ "${wins#* $w }" = "$wins" ]; then ' +
                'printf "%s\t0\tgone\n" "$id"; continue; fi; ' +
                'if [ -z "$f" ] || [ ! -f "$f" ]; then printf "%s\t0\tok\n" "$id"; continue; fi; ' +
                'm=$(stat -c %Y "$f"); ms=$(stat -c %.3Y "$f" | tr -d .); ' +
                'if [ $((now - m)) -gt 1800 ]; then printf "%s\t%s\tstale\n" "$id" "$ms"; continue; fi; ' +
                'state=ok; ' +
                'if [ "$m" -ge "$st" ] && tail -n 40 "$f" | grep -E "\\"type\\":\\"(user|assistant)\\"" | tail -n 1 ' +
                '| grep -qF "\\"text\\":\\"[Request interrupted by user"; then state=interrupted; fi; ' +
                'printf "%s\t%s\t%s\n" "$id" "$ms" "$state"; ' +
                'done', "sh"].concat(args)
            aiCheck.running = true
        }
    }

    // ── Uso de IA: avisos al 80/90/100 % y al renovarse el límite ──────────
    // Lee AiUsage (ai-usage.sh, cada 60 s). Por ventana (5 h / semanal /
    // mensual) avisa una vez por umbral y ventana (la clave incluye el reset).
    // Al pasar la hora de reset, si se había usado ≥50 %, avisa de que el
    // límite se ha renovado y fuerza una relectura.
    property var _usageStage: ({})      // "agent:campo:reset" → 0..3
    property var _usageTrack: ({})      // "agent:campo" → { reset, pct, done }
    function _windowLabel(field, secs) {
        if (secs > 0) {
            if (secs <= 6 * 3600) return Math.round(secs / 3600) + "h"
            if (secs <= 8 * 86400) return I18n.tr("weekly")
            return I18n.tr("monthly")
        }
        return field === "five_hour" ? "5h" : I18n.tr("weekly")
    }
    function _usageCheck() {
        for (const agent of ["claude", "codex"]) {
            const d = AiUsage[agent]
            if (!d || !d.ok) continue
            for (const field of ["five_hour", "seven_day"]) {
                const pct = d[field], reset = d[field + "_reset"]
                if (pct === null || pct === undefined || !reset) continue
                const label = _windowLabel(field, d[field + "_window"])
                const tk = agent + ":" + field
                const prev = _usageTrack[tk]
                const tr = Object.assign({}, _usageTrack)
                tr[tk] = { reset: reset, label: label,
                           pct: prev && prev.reset === reset ? Math.max(prev.pct, pct) : pct,
                           done: prev && prev.reset === reset ? prev.done : false }
                root._usageTrack = tr

                const stage = pct >= 100 ? 3 : pct >= 90 ? 2 : pct >= 80 ? 1 : 0
                const key = tk + ":" + reset
                const seen = _usageStage[key] || 0
                if (stage <= seen) continue
                const st = Object.assign({}, _usageStage)
                st[key] = stage
                root._usageStage = st
                // Primera lectura de esta ventana (arranque): sin aviso.
                if (!_ready || !prev) continue
                const resetAt = Qt.formatTime(new Date(reset * 1000), Settings.clock24h ? "HH:mm" : "h:mm AP")
                show({ logo: agent, title: aiName(agent) + " · " + label,
                       value: stage === 3 ? I18n.tr("Limit hit · resets %1").arg(resetAt)
                                          : I18n.tr("%1% used").arg(Math.round(pct)),
                       valueColor: stage >= 2 ? Theme.red : Theme.yellow, action: "aiusage" }, 7000)
            }
        }
    }
    Connections {
        target: AiUsage
        function onClaudeChanged() { root._usageCheck() }
        function onCodexChanged() { root._usageCheck() }
    }
    Timer {
        interval: 20000
        repeat: true
        running: true
        onTriggered: {
            const now = Date.now() / 1000
            let refreshed = false
            const tr = Object.assign({}, root._usageTrack)
            for (const tk in tr) {
                const t = tr[tk]
                if (t.done || now < t.reset) continue
                tr[tk] = Object.assign({}, t, { done: true })
                refreshed = true
                if (t.pct < 50) continue
                const agent = tk.split(":")[0]
                root.show({ logo: agent, title: root.aiName(agent),
                            value: I18n.tr("%1 limit refreshed").arg(t.label),
                            valueColor: Theme.green, action: "aiusage" }, 8000)
                root.playDoneSound()
            }
            root._usageTrack = tr
            if (refreshed) AiUsage.refresh(true)
        }
    }

    // ── Captura de pantalla: miniatura unos segundos ────────────────────────
    // ScreenCapture copia la imagen final a $XDG_RUNTIME_DIR y llama a
    // `qs ipc call island screenshot <preview> <ruta guardada|"">`.
    property var shot: null             // { preview, path, t, title, subtitle }
    // title/subtitle/ms opcionales (p. ej. la foto del intruso).
    function showShot(preview, path, title, subtitle, ms) {
        root.shot = { preview: preview, path: path || "", t: Date.now(), title: title || "", subtitle: subtitle || "" }
        shotTimer.interval = ms || 6000
        shotTimer.restart()
    }
    function holdShot() { if (shot) shotTimer.restart() }
    function dismissShot() { shotTimer.stop(); root.shot = null }
    Timer {
        id: shotTimer
        interval: 6000
        onTriggered: root.shot = null
    }

    // ── Portapapeles: aviso "Copiado" con un trozo del texto ────────────────
    // Clipboard emite copied() en cada copia; aquí se mira el tipo. Las
    // contraseñas (KeePassXC marca x-kde-passwordManagerHint) se ocultan y las
    // imágenes justo después de una captura no se anuncian (ya sale la miniatura).
    Connections {
        target: Clipboard
        function onCopied() { if (root._ready && !clipProc.running) clipProc.running = true }
    }
    Process {
        id: clipProc
        command: ["sh", "-c",
            'types=$(wl-paste --list-types 2>/dev/null); ' +
            'case "$types" in ' +
            '*x-kde-passwordManagerHint*) echo secret ;; ' +
            '*text/plain*|*UTF8_STRING*|*TEXT*) printf "text\\t"; wl-paste -n -t text 2>/dev/null | head -c 300 | tr "\\n\\t\\r" "   " ;; ' +
            '*image/*) echo image ;; ' +
            'esac']
        stdout: StdioCollector {
            onStreamFinished: {
                const out = this.text || ""
                const tab = out.indexOf("\t")
                const kind = (tab >= 0 ? out.slice(0, tab) : out).trim()
                if (kind === "image" && root.shot && Date.now() - root.shot.t < 4000) return
                const val = kind === "secret" ? "••••••••"
                          : kind === "image" ? I18n.tr("Image")
                          : kind === "text" ? out.slice(tab + 1).replace(/\s+/g, " ").trim()
                          : ""
                if (val === "") return
                root.show({ icon: root.icons.copy, iconColor: Theme.accent, title: I18n.tr("Copied"),
                            value: val, valueColor: Theme.fgMuted, action: "clipboard" }, 2500)
            }
        }
    }

    // ── Seguridad: puertos nuevos, firewall, Wazuh, ping ────────────────────
    property var _portSeen: ({})
    property var _byeAt: ({})               // ip → ms del último aviso de salida SSH
    Connections {
        target: Firewall
        function onSshDisconnected(ip) {
            root._byeAt[ip] = Date.now()
            root.show({ icon: "\u{f0343}", iconColor: Theme.yellow, title: I18n.tr("SSH disconnected"),
                        value: FwActivity.known[ip] || ip, valueColor: Theme.fgMuted, action: "firewall" }, 4000)
        }
        function onNewPortsChanged() {
            const seen = Object.assign({}, root._portSeen)
            for (const l of Firewall.newPorts) {
                const k = Firewall.portKey(l)
                if (seen[k]) continue
                seen[k] = true
                if (root._ready)
                    root.show({ icon: root.icons.alert, iconColor: Theme.yellow, title: I18n.tr("New open port"),
                                value: l.proto.toUpperCase() + " " + l.port + (l.process ? " · " + l.process : ""),
                                valueColor: Theme.yellow, action: "firewall" }, 8000)
            }
            root._portSeen = seen
        }
        function onFirewallChanged() {
            if (!root._ready || !Firewall.firewallInstalled || !Firewall.loaded) return
            root.show({ icon: root.icons.shield, iconColor: Firewall.firewallOn ? Theme.green : Theme.red,
                        title: I18n.tr("Firewall"),
                        value: Firewall.firewallOn ? I18n.tr("On") : I18n.tr("Off"),
                        valueColor: Firewall.firewallOn ? Theme.green : Theme.red, action: "firewall" }, 4000)
        }
    }
    Connections {
        target: Wazuh
        function onRunningChanged() {
            if (!root._ready) return
            root.show({ icon: root.icons.shield, iconColor: Wazuh.running ? Theme.green : Theme.red,
                        title: "Wazuh", value: Wazuh.running ? I18n.tr("Running") : I18n.tr("Stopped"),
                        valueColor: Wazuh.running ? Theme.green : Theme.red }, 4000)
        }
    }
    property string _pingKey: ""
    Connections {
        target: PingMonitor
        function onOnlineChanged() { root._pingCheck() }
        function onHasResultChanged() { root._pingCheck() }
    }
    function _pingCheck() {
        if (!PingMonitor.hasResult || PingMonitor.targetIp === "") return
        const key = PingMonitor.targetIp + ":" + PingMonitor.online
        const prevIp = _pingKey.slice(0, _pingKey.lastIndexOf(":"))
        const changed = key !== _pingKey && prevIp === PingMonitor.targetIp
        root._pingKey = key
        if (!changed || !_ready) return
        show({ icon: PingMonitor.online ? icons.wifi : icons.wifiOff,
               iconColor: PingMonitor.online ? Theme.green : Theme.red,
               title: PingMonitor.targetIp, value: PingMonitor.online ? I18n.tr("Up") : I18n.tr("Down"),
               valueColor: PingMonitor.online ? Theme.green : Theme.red }, 5000)
    }

    // ── Actualizaciones ─────────────────────────────────────────────────────
    // Aviso cuando aumentan las pendientes, y actividad en vivo mientras corre
    // pacman/yay: se sigue /var/log/pacman.log (tail -F) para la fase y los
    // paquetes hechos; el total sale de PackageUpdates. Termina cuando ya no
    // queda ningún pacman/yay vivo (ver updPoll).
    property int _updPrev: -1
    Connections {
        target: PackageUpdates
        function onCountChanged() {
            const n = PackageUpdates.count
            if (root._ready && root._updPrev >= 0 && n > root._updPrev && !root.upd)
                root.show({ icon: root.icons.pkg, iconColor: Theme.accent, title: I18n.tr("Updates available"),
                            value: I18n.tr("%1 packages").arg(n), valueColor: Theme.accent, action: "updates" }, 5000)
            if (!PackageUpdates.loading) root._updPrev = n
        }
    }
    // { phase: "download" | "install" | "wait" | "build", done, total, pkg, ok }
    // ok: ya se completó alguna transacción (al terminar → "Update complete").
    property var upd: null
    readonly property real updProgress: upd && upd.total > 0 ? Math.min(1, upd.done / upd.total) : 0
    function _updTotal() {
        return (PackageUpdates.packages || []).filter(p => p.source !== "flatpak").length
    }
    Process {
        running: true
        command: ["tail", "-n0", "-F", "/var/log/pacman.log"]
        stdout: SplitParser {
            onRead: (line) => root._pacmanLine(line)
        }
    }
    function _pacmanLine(line) {
        let m
        if ((m = line.match(/\[PACMAN\] Running '([^']*)'/))) {
            const cmd = " " + m[1] + " "
            const install = / -U/.test(cmd)
            if (!install && !/ -S/.test(cmd)) return
            // yay lanza varios pacman (-Sy, -S repo, -U AUR): se sigue en la misma actividad.
            if (upd) {
                root.upd = Object.assign({}, upd, { phase: install ? "install" : "download" })
                return
            }
            // Total conocido solo en -Syu (pacman directo); con yay lo pone el sondeo.
            root.upd = { phase: install ? "install" : "download", done: 0, pkg: "", ok: false,
                         total: /-S\S*u|--sysupgrade/.test(cmd) ? _updTotal() : 0 }
        } else if (line.indexOf("[ALPM] transaction started") !== -1) {
            if (upd) root.upd = Object.assign({}, upd, { phase: "install" })
        } else if ((m = line.match(/\[ALPM\] (upgraded|installed|removed|reinstalled|downgraded) (\S+)/))) {
            if (!upd) return
            const done = upd.done + 1
            root.upd = Object.assign({}, upd, { done: done, pkg: m[2],
                                                total: upd.total > 0 ? Math.max(upd.total, done) : 0 })
        } else if (line.indexOf("[ALPM] transaction completed") !== -1) {
            // No se cierra aquí: yay puede seguir (preguntas, compilar AUR).
            // Lo cierra el sondeo cuando ya no queda pacman/yay.
            if (!upd) return
            root.upd = Object.assign({}, upd, { ok: true })
            if (!updPoll.running) updPoll.running = true
        } else if (/\[ALPM\] transaction (failed|interrupted)/.test(line)) {
            if (!upd) return
            root.upd = null
            show({ icon: icons.alert, iconColor: Theme.red, title: I18n.tr("Update failed"),
                   value: I18n.tr("See pacman output"), valueColor: Theme.red }, 6000)
        }
    }
    function _updFinish() {
        const u = upd
        root.upd = null
        if (!u || !u.ok) return     // cancelado o solo -Sy: se quita sin aviso
        show({ icon: icons.pkg, iconColor: Theme.green, title: I18n.tr("Update complete"),
               value: I18n.tr("%1 packages").arg(u.done), valueColor: Theme.green }, 5000)
        PackageUpdates.refresh()
    }
    // Sondeo cada 2 s mientras hay actividad: ¿sigue vivo pacman o un helper
    // de AUR? yay suelta el lock de pacman mientras pregunta (clean build,
    // diffs…) y mientras compila, así que el lock no sirve para saber si
    // terminó. Sin proceso dos veces seguidas (una si ya completó) → fin.
    // Salida: "<lock 0|1> <makepkg 0|1>" y luego las líneas de pgrep -a.
    property int _updMisses: 0
    onUpdChanged: if (!upd) _updMisses = 0
    Process {
        id: updPoll
        command: ["sh", "-c",
            'l=0; [ -e /var/lib/pacman/db.lck ] && l=1; ' +
            'b=0; pgrep -x makepkg >/dev/null && b=1; ' +
            'echo "$l $b"; pgrep -a -x "pacman|yay|paru|pikaur|trizen|aura"']
        stdout: StdioCollector {
            onStreamFinished: {
                const u = root.upd
                if (!u) return
                const lines = (this.text || "").split("\n").filter(l => l !== "")
                const flags = (lines.shift() || "0 0").split(" ")
                if (lines.length === 0) {
                    root._updMisses++
                    if (root._updMisses >= (u.ok ? 1 : 2)) root._updFinish()
                    return
                }
                root._updMisses = 0
                const patch = {}
                if (u.total === 0 && lines.some(l => /\s-S\S*u|--sysupgrade/.test(l)))
                    patch.total = Math.max(root._updTotal(), u.done)
                if (flags[0] !== "1") {
                    const phase = flags[1] === "1" ? "build" : "wait"
                    if (u.phase !== phase) patch.phase = phase
                }
                if (Object.keys(patch).length > 0) root.upd = Object.assign({}, u, patch)
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.upd !== null
        onTriggered: if (!updPoll.running) updPoll.running = true
    }

    // ── Teclado: Bloq Mayús y distribución ─────────────────────────────────
    // Bloq Mayús: LEDs de /sys/class/leds/*capslock (sysfs no avisa por
    // inotify de cambios del kernel, así que se releen cada 250 ms en proceso,
    // sin lanzar comandos). Distribución: evento "activelayout" de Hyprland.
    property var _capsPaths: []
    property bool capsLock: false
    property bool _capsInit: false
    Process {
        running: true
        command: ["sh", "-c", "ls -d /sys/class/leds/*capslock 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root._capsPaths = (this.text || "").split("\n").filter(l => l !== "")
                                                    .map(p => p + "/brightness")
        }
    }
    Instantiator {
        id: capsFiles
        model: root._capsPaths
        delegate: FileView {
            required property string modelData
            path: modelData
            blockLoading: true
            printErrors: false
        }
    }
    Timer {
        interval: 250
        repeat: true
        running: root._capsPaths.length > 0
        onTriggered: {
            let on = false
            for (let i = 0; i < capsFiles.count; i++) {
                const fv = capsFiles.objectAt(i)
                if (!fv) continue
                fv.reload()
                if (parseInt(fv.text()) > 0) on = true
            }
            if (!root._capsInit) { root._capsInit = true; root.capsLock = on; return }
            if (on === root.capsLock) return
            root.capsLock = on
            root.show({ icon: root.icons.capslock, iconColor: on ? Theme.accent : Theme.fgMuted,
                        title: I18n.tr("Caps Lock"), value: on ? I18n.tr("On") : I18n.tr("Off"),
                        valueColor: on ? Theme.accent : Theme.fgMuted }, 1500)
        }
    }
    property string _layout: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return
            const data = String(event.data)
            const layout = data.slice(data.indexOf(",") + 1)
            if (layout === "" || layout === root._layout) return
            const first = root._layout === ""
            root._layout = layout
            if (first || !root._ready) return
            root.show({ icon: root.icons.keyboard, iconColor: Theme.accent, title: I18n.tr("Keyboard"),
                        value: layout, valueColor: Theme.accent }, 2000)
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "hyprctl devices -j | jq -r '[.keyboards[] | select(.main)][0].active_keymap // .keyboards[0].active_keymap'"]
        stdout: StdioCollector {
            onStreamFinished: { const l = (this.text || "").trim(); if (l && root._layout === "") root._layout = l }
        }
    }

    // ── Preguntas con botones (USB nuevo, app nueva en red) ─────────────────
    // Cola: el notch enseña la primera (Bar/Notch.qml, modo "prompt"). Sin
    // respuesta en `ms` se responde "timeout" (USB: sigue bloqueado; red: se
    // recuerda la app). El ratón encima congela la cuenta atrás.
    // { kind, key, icon, iconColor, title, value, valueColor,
    //   buttons: [{ id, label, color }], ms, data }
    property var prompts: []
    readonly property var prompt: prompts.length > 0 ? prompts[0] : null
    property string _promptKey: ""
    function ask(p) {
        if (prompts.some(x => x.key === p.key)) return
        root.prompts = prompts.concat([Object.assign({
            icon: "", iconColor: "white", title: "", value: "", valueColor: Theme.fgMuted,
            buttons: [], ms: 20000, data: ({}), t: Date.now()
        }, p)])
    }
    function promptAnswer(choice) {
        const p = prompt
        if (!p) return
        // SSH: "Allow" no cierra la pregunta, pasa a pedir la contraseña
        if ((p.kind === "ssh" || p.kind === "root") && choice === "allow" && !p.data.pw) { _sshAskPassword(p); return }
        promptTimer.stop()
        root.prompts = prompts.slice(1)
        if (p.kind === "usb") UsbGuard.answer(p.data.id, choice)
        else if (p.kind === "alarm") {
            if (choice === "snooze") Alarms.snooze(5)
            else Alarms.stop()
        }
        else if (p.kind === "mem") {
            if (choice === "kill") MemWatch.kill(p.data.app)
            else MemWatch.snooze(p.data.level)
        }
        else if (p.kind === "ssh" && choice !== "allowed") _sshDeclined(p.data.ip)
        else if (p.kind === "root" && choice !== "allowed") root._rootMutedUntil = Date.now() + 60000
        else if ((p.kind === "scan" || p.kind === "brute") && choice === "block") {
            if (!p.data.demo) FwBlock.block(p.data.ip, 60)
            show({ icon: icons.shield, iconColor: Theme.red, title: I18n.tr("Blocked"),
                   value: p.data.ip + " · " + I18n.tr("1 hour"), valueColor: Theme.fgMuted, action: "firewall" }, 3000)
        }
    }
    function holdPrompt() { if (prompt) promptTimer.restart() }
    onPromptChanged: {
        const k = prompt ? prompt.key : ""
        if (k === _promptKey) return
        root._promptKey = k
        if (!prompt) return
        promptTimer.interval = prompt.ms
        promptTimer.restart()
    }
    Timer {
        id: promptTimer
        onTriggered: root.promptAnswer("timeout")
    }

    // ── Alarmas (pestaña Alarm del selector; Services/Alarms.qml) ──────────
    // Alarma en edición: { id ("" = nueva), h, m, days, label }, o null (lista).
    property var alarmEdit: null
    function editAlarm(a) {
        root.alarmEdit = a ? { id: a.id, h: a.h, m: a.m, days: a.days.slice(), label: a.label }
                           : { id: "", h: 7, m: 0, days: [], label: "" }
    }
    function setAlarmEdit(patch) { root.alarmEdit = Object.assign({}, alarmEdit, patch) }
    function saveAlarm() {
        const e = alarmEdit
        if (!e) return
        let a
        if (e.id === "") a = Alarms.add(e.h, e.m, e.days, e.label)
        else {
            Alarms.update(e.id, { h: e.h, m: e.m, days: e.days, label: e.label, on: true })
            a = Alarms.alarms.find(x => x.id === e.id)
        }
        root.alarmEdit = null
        // Como en el móvil: "Alarm set for 7 h 20 min from now".
        if (a) show({ icon: icons.alarm, iconColor: Theme.magenta, title: I18n.tr("Alarm set"),
                      value: Alarms.untilText(Alarms.nextFire(a)), valueColor: Theme.fgMuted }, 2500)
    }
    function deleteAlarm() {
        if (alarmEdit && alarmEdit.id !== "") Alarms.remove(alarmEdit.id)
        root.alarmEdit = null
    }
    Connections {
        target: Alarms
        function onRing(a) {
            const time = Alarms.timeText(a.h, a.m, Settings.clock24h)
            // Delante de cualquier otra pregunta: una alarma no espera turno.
            root.prompts = [{
                kind: "alarm", key: "alarm:" + a.id + ":" + Date.now(),
                icon: root.icons.alarm, iconColor: Theme.magenta,
                title: (a.label || I18n.tr("Alarm")) + " · " + time,
                value: I18n.tr(Alarms.daysText(a.days)), valueColor: Theme.fgMuted,
                buttons: [{ id: "snooze", label: I18n.tr("Snooze 5 min"), color: Theme.yellow },
                          { id: "stop", label: I18n.tr("Stop"), color: Theme.magenta }],
                ms: 5 * 60000, data: ({}), t: Date.now()
            }].concat(root.prompts.filter(p => p.kind !== "alarm"))
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell", "-i", "alarm-clock",
                a.label || I18n.tr("Alarm"), time])
        }
    }
    // Suena en bucle hasta Stop / Snooze (o 5 min sin respuesta).
    Timer {
        interval: 2600
        repeat: true
        triggeredOnStart: true
        running: Alarms.ringing !== null
        onTriggered: root.playDoneSound()
    }

    // ── USB (USBGuard) ──────────────────────────────────────────────────────
    function _usbPrompt(id, name, kind, suspicious, demo) {
        ask({ kind: demo ? "demo" : "usb", key: "usb:" + id,
              icon: suspicious ? icons.alert : icons.usb, iconColor: suspicious ? Theme.red : Theme.yellow,
              title: suspicious ? I18n.tr("Suspicious USB device") : I18n.tr("New %1").arg(I18n.tr(UsbGuard.kindLabel(kind))),
              value: name + " · " + I18n.tr("blocked"), valueColor: suspicious ? Theme.red : Theme.fgMuted,
              buttons: [{ id: "allow", label: I18n.tr("Allow once"), color: Theme.green },
                        { id: "always", label: I18n.tr("Always"), color: Theme.accent },
                        { id: "block", label: I18n.tr("Block"), color: Theme.red }],
              ms: 30000, data: { id: id } })
        playDoneSound()
    }
    Connections {
        target: UsbGuard
        function onBlocked(id, name, kind, suspicious) { root._usbPrompt(id, name, kind, suspicious, false) }
        function onConnected(name, kind) {
            root.show({ icon: root.icons.usb, iconColor: Theme.accent, title: name,
                        value: I18n.tr(UsbGuard.kindLabel(kind)), valueColor: Theme.fgMuted }, 2500)
        }
    }

    // ── Contraseñas fallidas ────────────────────────────────────────────────
    Connections {
        target: AuthWatch
        function onFailed(service, user, where, count) {
            // Durante un ataque ya avisa BruteWatch; no un aviso por intento
            const from = (where.match(/(\S+)$/) || [])[1] || ""
            if (where.indexOf(I18n.tr("from %1").arg("")) === 0 && BruteWatch.isAttacking(from)) return
            root.show({ icon: root.icons.lockAlert, iconColor: Theme.red,
                        title: I18n.tr("Wrong password") + " · " + I18n.tr(AuthWatch.label(service)),
                        value: (count > 1 ? "×" + count + "  " : "") + user + (where !== "" ? " · " + where : ""),
                        valueColor: Theme.red, action: "firewall" }, 6000)
            // Intentos remotos: también al centro de notificaciones.
            if (where.indexOf(I18n.tr("from %1").arg("")) === 0)
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell",
                    I18n.tr("Failed %1 login").arg(AuthWatch.label(service)), user + " " + where])
        }
        function onSshLogin(user, ip, method) {
            root.show({ icon: "\u{f0342}", iconColor: Theme.green,
                        title: I18n.tr("SSH login") + " · " + user,
                        value: (FwActivity.known[ip] || ip) + " · " + I18n.tr(FwActivity.where(ip)) + " · " + method,
                        valueColor: "white", action: "firewall" }, 8000)
        }
        function onSshLogout(user, ip) { root._sshBye(user, ip) }
        function onRootLocked(service, user, who) { root._rootPrompt(service, who, false) }
        function onInvalidUser(user, ip) {
            root.show({ icon: root.icons.lockAlert, iconColor: Theme.yellow,
                        title: I18n.tr("SSH: no user \"%1\"").arg(user),
                        value: I18n.tr("Log in as %1").arg("ssh " + Quickshell.env("USER") + "@" + (Sshd.localIp || "this-pc")),
                        valueColor: Theme.yellow, action: "firewall" }, 10000)
        }
        function onLocked(service, user) {
            root.show({ icon: root.icons.lockAlert, iconColor: Theme.red, title: I18n.tr("Account locked"),
                        value: user + " · " + I18n.tr(AuthWatch.label(service)), valueColor: Theme.red }, 10000)
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell",
                I18n.tr("Account locked"), I18n.tr("Too many failed passwords for %1").arg(user)])
        }
        function onAwaySummary(count, photos) {
            const what = count === 1 ? I18n.tr("1 failed unlock") : I18n.tr("%1 failed unlocks").arg(count)
            // Con foto del intruso: tarjeta con la foto (abrir / carpeta).
            if (photos && photos.length > 0) {
                const p = photos[photos.length - 1]
                root.showShot(p, p, what,
                              photos.length > 1 ? I18n.tr("%1 intruder photos").arg(photos.length) : I18n.tr("Intruder photo"), 20000)
            } else {
                root.show({ icon: root.icons.lockAlert, iconColor: Theme.red, title: I18n.tr("While you were away"),
                            value: what, valueColor: Theme.red }, 10000)
            }
            root.playDoneSound()
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell",
                I18n.tr("Failed unlock attempts"), I18n.tr("%1 wrong passwords on the lock screen").arg(count)])
        }
    }

    // ── Memoria casi llena: ¿cerrar la app que más usa? ─────────────────────
    function _memPrompt(level, avail, app, appBytes, demo) {
        const crit = level === "critical"
        const buttons = []
        if (app !== "") buttons.push({ id: "kill", label: I18n.tr("Close %1").arg(app), color: Theme.red })
        buttons.push({ id: "ignore", label: I18n.tr("Ignore"), color: Theme.fgMuted })
        ask({ kind: demo ? "demo" : "mem", key: "mem:" + level,
              icon: icons.memory, iconColor: crit ? Theme.red : Theme.yellow,
              title: crit ? I18n.tr("Memory full, system may freeze") : I18n.tr("Memory almost full"),
              value: I18n.tr("%1 left").arg(DiskClean.human(avail))
                     + (app !== "" ? " · " + I18n.tr("%1 uses %2").arg(app).arg(DiskClean.human(appBytes)) : ""),
              valueColor: crit ? Theme.red : Theme.yellow,
              buttons: buttons, ms: 30000, data: { app: app, level: level } })
        playDoneSound()
    }
    Connections {
        target: MemWatch
        function onPressure(level, avail, app, appBytes) { root._memPrompt(level, avail, app, appBytes, false) }
    }

    // ── SSH con sshd apagado: ¿encenderlo? ──────────────────────────────────
    // Alguien llama al puerto 22 y sshd está apagado (le sale "connection
    // refused"). La isla pregunta 20 s: Allow → contraseña de este usuario
    // (unix_chkpwd, por stdin) → sshd encendido, y el otro equipo reintenta.
    // Decline / sin respuesta → esa IP no vuelve a preguntar en 2 min.
    // Encender sshd lo abre para toda la red, no solo para esa IP.
    property var _sshMuted: ({})        // ip → ms hasta cuando no se pregunta
    property bool sshPwBusy: false
    signal sshPwWrong()
    function _sshPrompt(ip, who, demo) {
        if (!demo && (Sshd.running || Date.now() < (_sshMuted[ip] || 0))) return
        // A quien está probando contraseñas no se le ofrece encender SSH
        if (!demo && BruteWatch.isAttacking(ip)) return
        ask({ kind: "ssh", key: "ssh:" + ip, style: "call",
              icon: "\u{f120}", iconColor: Theme.yellow,          // >_
              title: I18n.tr("SSH request"),
              value: who + " · " + I18n.tr(FwActivity.where(ip)),
              buttons: [{ id: "decline", label: I18n.tr("Decline") },
                        { id: "allow", label: I18n.tr("Allow"), color: Theme.green, primary: true }],
              ms: 20000, data: { ip: ip, who: who, demo: demo } })
    }
    // SSH y root lock comparten la fase de contraseña (Notch: sshPwStage)
    function _sshAskPassword(p) {
        // Clave nueva → la cuenta atrás empieza otra vez (20 s para escribir)
        root.prompts = [Object.assign({}, p, {
            key: p.key + ":pw",
            title: p.kind === "root" ? I18n.tr("Your password to unlock root") : I18n.tr("Allow %1?").arg(p.data.who),
            icon: "\u{f033e}", iconColor: "white",                // candado
            buttons: [{ id: "decline", label: I18n.tr("Cancel") },
                      { id: "allow", label: I18n.tr("Allow"), color: Theme.green, primary: true }],
            data: Object.assign({}, p.data, { pw: true, tries: 0 })
        })].concat(prompts.slice(1))
    }
    function sshPassword(pw) {
        const p = prompt
        if (!p || (p.kind !== "ssh" && p.kind !== "root") || !p.data.pw || sshPwBusy || pw === "") return
        root.sshPwBusy = true
        // Root de verdad: Firewall.unlockRoot (también lo usa el panel)
        if (p.kind === "root" && !p.data.demo) {
            if (!Firewall.unlockRoot(pw, rootUnlockMin, "island")) root.sshPwBusy = false
            return
        }
        // Demo de root: no desbloquea nada, solo comprueba la contraseña
        const proc = p.kind === "root" ? rootProc : chkProc
        proc._pw = pw
        proc.running = true
    }
    // Contraseña mal: hasta 3 intentos, luego se cierra con `failText`
    function _pwWrong(p, failText) {
        const tries = p.data.tries + 1
        if (tries >= 3) {
            promptAnswer("decline")
            show({ icon: icons.lockAlert, iconColor: Theme.red, title: I18n.tr("Wrong password"),
                   value: failText, valueColor: Theme.red }, 5000)
            return
        }
        root.prompts = [Object.assign({}, p, {
            title: I18n.tr("Wrong password · %1 left").arg(3 - tries), titleColor: Theme.red,
            data: Object.assign({}, p.data, { tries: tries })
        })].concat(prompts.slice(1))
        holdPrompt()
        sshPwWrong()
    }
    function _sshChecked(ok) {
        root.sshPwBusy = false
        const p = prompt
        if (!p || p.kind !== "ssh" || !p.data.pw) return
        if (ok) {
            promptAnswer("allowed")
            if (!p.data.demo) Sshd.start()
            show({ icon: FwActivity.kinds.ssh.icon, iconColor: Theme.green, title: I18n.tr("SSH allowed"),
                   value: "ssh " + Quickshell.env("USER") + "@" + (Sshd.localIp || "this-pc"), valueColor: Theme.green }, 10000)
            return
        }
        _pwWrong(p, I18n.tr("SSH stays off"))
    }
    function _sshDeclined(ip) {
        const m = Object.assign({}, _sshMuted)
        m[ip] = Date.now() + 2 * 60000
        root._sshMuted = m
    }
    // unix_chkpwd: comprueba la contraseña del propio usuario (setuid, la
    // lee de stdin hasta el \0). 0 = correcta.
    Process {
        id: chkProc
        property string _pw: ""
        command: ["/usr/bin/unix_chkpwd", Quickshell.env("USER"), "nullok"]
        stdinEnabled: true
        onStarted: { write(_pw + "\0"); _pw = ""; stdinEnabled = false }
        onExited: (code) => {
            stdinEnabled = true
            root._sshChecked(code === 0)
        }
    }
    Connections {
        target: FwActivity
        function onSshKnock(ip, who) { root._sshPrompt(ip, who, false) }
    }

    // Alguien salió de SSH (AuthWatch.sshLogout)
    function _sshBye(user, ip) {
        // Ya avisó el botón Disconnect (o salió por varias conexiones a la vez)
        if (Date.now() - (_byeAt[ip] || 0) < 10000) return
        _byeAt[ip] = Date.now()
        show({ icon: "\u{f0343}", iconColor: Theme.fgMuted,
               title: I18n.tr("SSH logout"),
               value: user + "@" + (FwActivity.known[ip] || ip),
               valueColor: Theme.fgMuted, action: "firewall" }, 6000)
        Firewall.refresh()
    }

    // ── Root lock: alguien conectado pidió root → ¿desbloquear 5 min? ───────
    // AuthWatch.rootLocked (sudo/su rechazado) → pregunta. Allow → tu
    // contraseña → /usr/local/sbin/qs-rootlock-allow (por sudo, sin contraseña)
    // la comprueba como root, mira que la petición sale de este escritorio y
    // deja root abierto 5 min; luego el otro vuelve a hacer sudo.
    readonly property int rootUnlockMin: 5
    property real _rootMutedUntil: 0
    function _rootPrompt(service, who, demo) {
        if (!demo && Date.now() < _rootMutedUntil) return
        ask({ kind: "root", key: "root", style: "call",
              icon: "\u{f033e}", iconColor: Theme.red,           // candado
              title: I18n.tr("Root request") + " · " + I18n.tr(AuthWatch.label(service)),
              value: who !== "" ? I18n.tr("%1 is connected").arg(who) : I18n.tr("Someone is connected remotely"),
              buttons: [{ id: "decline", label: I18n.tr("Deny") },
                        { id: "allow", label: I18n.tr("Allow %1 min").arg(rootUnlockMin), color: Theme.yellow, primary: true }],
              ms: 20000, data: { who: who, demo: !!demo } })
    }
    function _rootChecked(code, err) {
        root.sshPwBusy = false
        const p = prompt
        if (!p || p.kind !== "root" || !p.data.pw) return
        if (code === 0) {
            promptAnswer("allowed")
            show({ icon: "\u{f0fc6}", iconColor: Theme.yellow, title: I18n.tr("Root unlocked · %1 min").arg(rootUnlockMin),
                   value: I18n.tr("They can run sudo again"), valueColor: Theme.yellow, action: "firewall" }, 8000)
            Firewall.refresh()
        } else if (code === 10) {
            _pwWrong(p, I18n.tr("Root stays locked"))
        } else {
            promptAnswer("decline")
            show({ icon: icons.lockAlert, iconColor: Theme.red, title: I18n.tr("Could not unlock root"),
                   value: code === 11 ? I18n.tr("Only from this desktop") : (err || I18n.tr("Is qs-rootlock-allow installed?")),
                   valueColor: Theme.red }, 8000)
        }
    }
    Process {
        id: rootProc
        property string _pw: ""
        command: ["/usr/bin/unix_chkpwd", Quickshell.env("USER"), "nullok"]
        stdinEnabled: true
        onStarted: { write(_pw + "\0"); _pw = ""; stdinEnabled = false }
        onExited: (code) => {
            stdinEnabled = true
            root._rootChecked(code === 0 ? 0 : 10, "")
        }
    }
    Connections {
        target: Firewall
        function onUnlockResult(code, err, from) {
            if (from === "island") { root._rootChecked(code, err); return }
            // Desbloqueado desde el panel: aviso igual y fuera la pregunta pendiente
            if (code !== 0) return
            if (root.prompt && root.prompt.kind === "root") root.promptAnswer("allowed")
            root.show({ icon: "\u{f0fc6}", iconColor: Theme.yellow, title: I18n.tr("Root unlocked · %1 min").arg(root.rootUnlockMin),
                        value: I18n.tr("They can run sudo again"), valueColor: Theme.yellow, action: "firewall" }, 8000)
        }
    }

    // ── Escaneo de puertos ──────────────────────────────────────────────────
    // r: informe de ScanWatch. Lo importante es qué puertos encontró abiertos;
    // la pregunta ofrece bloquear la IP una hora (FwBlock).
    // ── Fuerza bruta (BruteWatch) ───────────────────────────────────────────
    // Desde otra máquina: BruteWatch ya la ha bloqueado 1 h; aquí solo se
    // avisa (qué servicio, quién). En este PC (sudo, pantalla de bloqueo…) igual.
    function _bruteAlert(b, demo) {
        const what = b.kind === "auth" ? I18n.tr("%1 wrong passwords").arg(b.count)
                                       : I18n.tr("%1 connections in a row").arg(b.count)
        const users = b.users.length > 0 ? " · " + b.users.slice(0, 3).join(", ") : ""
        const title = I18n.tr("%1 brute force").arg(b.service)
        if (!b.ip) {
            show({ icon: icons.lockAlert, iconColor: Theme.red, title: title,
                   value: what + users, valueColor: Theme.red, action: "firewall" }, 10000)
            return
        }
        // Fuera la pregunta de "¿Allow SSH?" de esa misma IP
        if (!demo) root.prompts = prompts.filter(p => !(p.kind === "ssh" && p.data.ip === b.ip))
        HostNames.lookup(b.ip)
        const name = FwActivity.known[b.ip] || HostNames.label(b.ip)
        const blocked = b.blocked || demo
        show({ icon: icons.lockAlert, iconColor: Theme.red,
               title: title + (blocked ? " · " + I18n.tr("blocked") : ""),
               value: _bruteValue(b.ip), valueColor: Theme.red, action: "firewall",
               brute: { ip: b.ip, blocked: blocked } }, 10000)
        Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell", title,
            b.ip + (name ? " (" + name + ")" : "") + ": " + what + users
            + (blocked ? "\n" + I18n.tr("Blocked for 1 hour. Unblock it in the Firewall panel.") : "")])
    }
    // "Mac · 192.168.0.151"
    function _bruteValue(ip) {
        const name = FwActivity.known[ip] || HostNames.label(ip)
        return (name ? name + " · " : "") + ip
    }
    Connections {
        target: BruteWatch
        function onAttack(b) { if (!b.backfill) root._bruteAlert(b, false) }
    }

    function _scanAlert(r, demo) {
        ask({ kind: "scan", key: "scan:" + r.src, style: "call",
              icon: icons.radar, iconColor: Theme.red,
              title: ScanWatch.title(r),
              value: r.src + " · " + (r.open.length > 0 ? I18n.tr("open %1").arg(r.open.map(p => p.port).join(", "))
                                                        : I18n.tr("nothing open")),
              valueColor: r.open.length > 0 ? Theme.red : Theme.fgMuted,
              buttons: [{ id: "ignore", label: I18n.tr("Ignore") },
                        { id: "block", label: I18n.tr("Block 1 h"), color: Theme.red, primary: true, ink: "white" }],
              ms: 20000, data: { ip: r.src, demo: !!demo } })
    }
    Connections {
        target: ScanWatch
        function onScan(r) {
            root._scanAlert(r)
            const body = [I18n.tr("%1 probed %2 ports (%3 scan).").arg(r.src).arg(r.probed).arg(r.type)]
            if (r.open.length > 0) body.push(I18n.tr("Found open: %1").arg(FwActivity.portList(r.open, 12)))
            if (r.closed.length > 0) body.push(I18n.tr("Closed: %1").arg(FwActivity.portList(r.closed, 12)))
            body.push(I18n.tr("Blocked by the firewall: %1").arg(r.filtered.length))
            Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Quickshell",
                I18n.tr("Port scan detected"), body.join("\n")])
        }
    }

    // ── Actividad del firewall (panel → Activity) ───────────────────────────
    // Ping, SSH, conexiones y bloqueos de otras máquinas. Clic → panel del firewall.
    function _fwAlert(e) {
        const k = FwActivity.kinds[e.kind]
        const ping = e.kind === "ping"
        // IP baneada que vuelve a probar: "Banned IP · SSH · 52m left"
        const ban = FwBlock.blocked.find(b => b.ip === e.ip)
        const extra = e.kind === "banned" ? " · " + e.service
                      + (ban ? " · " + I18n.tr("%1m left").arg(Math.max(1, Math.round((ban.expires - Date.now()) / 60000))) : "")
                    : ping ? _pingCount(e.ip) : ""
        show({ icon: k.icon, iconColor: k.color, title: I18n.tr(k.label) + extra,
               value: _fwValue(e), valueColor: "white", action: "firewall",
               fwEvent: e, pingIp: ping ? e.ip : "", base: I18n.tr(k.label) }, ping ? 3000 : 5000)
    }

    // "Samsung · 192.168.0.117" si se sabe quién es (HostNames), si no
    // "192.168.0.117 · UDP 39189" / "… · Home network"
    function _fwValue(e) {
        const n = FwActivity.known[e.ip] || HostNames.label(e.ip || "")
        if (n) return n + " · " + e.ip
        if (e.kind === "banned") return e.ip
        return e.who + " · " + (e.kind === "connect" || e.kind === "blocked" ? e.service : e.where)
    }
    // El nombre llegó con el aviso ya en pantalla: se pone
    Connections {
        target: HostNames
        function onResolved(ip) {
            const a = root.alert
            if (a && a.fwEvent && a.fwEvent.ip === ip)
                root.alert = Object.assign({}, a, { value: root._fwValue(a.fwEvent) })
            else if (a && a.brute && a.brute.ip === ip)
                root.alert = Object.assign({}, a, { value: root._bruteValue(ip) })
        }
    }

    // Ping en directo: cada paquete (FwActivity.pingSeen, ~1/s) alarga el
    // aviso de esa IP 3 s más y sube la cuenta; se va cuando el ping para,
    // o como mucho a los 30 s.
    property var _pingRuns: ({})        // ip → { start, last, n }
    function _pingCount(ip) {
        const r = _pingRuns[ip]
        return r && r.n > 1 ? " ×" + r.n : ""
    }
    Connections {
        target: FwActivity
        function onPingSeen(ip) {
            const now = Date.now()
            const runs = Object.assign({}, root._pingRuns)
            const r = runs[ip]
            runs[ip] = r && now - r.last < 3500 ? { start: r.start, last: now, n: r.n + 1 }
                                                : { start: now, last: now, n: 1 }
            root._pingRuns = runs
            const a = root.alert
            if (!a || a.pingIp !== ip) return
            const left = 30000 - (now - runs[ip].start)
            if (left <= 0) return
            root.alert = Object.assign({}, a, { title: a.base + root._pingCount(ip) })
            alertTimer.interval = Math.min(3000, left)
            alertTimer.restart()
        }
    }
    Connections {
        target: FwActivity
        function onActivity(e) {
            // Los escaneos ya tienen su propio aviso (ScanWatch);
            // SSH con sshd apagado, la pregunta de Allow/Decline
            if (e.kind === "ssh" && !Sshd.running) return
            // El aviso de fuerza bruta de esa IP sigue en pantalla: no taparlo
            if (e.kind === "banned" && root.alert && root.alert.brute && root.alert.brute.ip === e.ip) return
            if (e.kind !== "scan") root._fwAlert(e)
        }
    }

    // ── Descargas ───────────────────────────────────────────────────────────
    Connections {
        target: DownloadWatch
        function onFinished(path) {
            root.show({ icon: root.icons.download, iconColor: Theme.green, title: I18n.tr("Downloaded"),
                        value: path.split("/").pop(), valueColor: Theme.fgMuted, action: "folder:" + path }, 5000)
        }
    }

    // ── Sesión anterior terminada de golpe ──────────────────────────────────
    Connections {
        target: CrashLog
        function onUnexpected(boot) {
            root.show({ icon: root.icons.bug, iconColor: boot.status === "crash" ? Theme.red : Theme.yellow,
                        title: I18n.tr("Unexpected shutdown"),
                        value: boot.status === "crash" ? I18n.tr("Crashed") : I18n.tr("Forced off"),
                        valueColor: Theme.fgMuted, action: "logs" }, 12000)
        }
    }

    // ── Perfil de energía automático ────────────────────────────────────────
    // Enchufado → Performance; con batería → Balanced; batería ≤ 20 % → Power
    // saver. Si lo cambias a mano se respeta hasta el próximo enchufar/desenchufar.
    readonly property string _autoProfile: !hasBattery ? ""
        : !discharging ? (Power.hasPerformance ? "performance" : "balanced")
        : batteryPct <= 20 ? "power-saver" : "balanced"
    property bool _profileManual: false
    property string _profileOurs: ""
    on_AutoProfileChanged: _applyProfile()
    on_ReadyChanged: if (_ready) _applyProfile()
    function _applyProfile() {
        const want = _autoProfile
        if (!_ready || want === "" || !Power.available || _profileManual) return
        if (Power.currentProfileKey === want) { root._profileOurs = want; return }
        root._profileOurs = want
        Power.set(want === "performance" ? PowerProfile.Performance
                  : want === "power-saver" ? PowerProfile.PowerSaver : PowerProfile.Balanced)
        profileAnnounce.restart()
    }
    // Tras el aviso de "Charging" (si lo hay), para no taparlo.
    Timer {
        id: profileAnnounce
        interval: 3300
        onTriggered: root.show({ icon: Power.icon, iconColor: Theme.accent, title: Power.name,
                                 value: !root.discharging ? I18n.tr("Plugged in")
                                      : root.batteryPct <= 20 ? I18n.tr("Battery low") : I18n.tr("On battery"),
                                 valueColor: Theme.fgMuted }, 2500)
    }
    // Cambio a mano (no hecho por nosotros) → se respeta.
    Connections {
        target: Power
        function onCurrentProfileKeyChanged() {
            if (root._ready && Power.currentProfileKey !== root._profileOurs) root._profileManual = true
        }
    }

    // ── Disco casi lleno ────────────────────────────────────────────────────
    function _diskAlert() {
        show({ icon: icons.disk, iconColor: Theme.red, title: I18n.tr("Low disk space"),
               value: I18n.tr("%1 free").arg(DiskClean.human(DiskClean.diskFree)),
               valueColor: Theme.red, action: "disk" }, 8000)
    }
    Connections {
        target: DiskClean
        function onLowSpaceChanged() { if (root._ready && DiskClean.lowSpace) root._diskAlert() }
    }
    // Recordatorio cada 4 h mientras siga lleno.
    Timer {
        interval: 4 * 3600 * 1000
        repeat: true
        running: DiskClean.lowSpace
        onTriggered: root._diskAlert()
    }

    // ── Clic en un aviso: acción asociada ───────────────────────────────────
    function alertClick() {
        const a = alert
        dismiss()
        if (!a || !a.action) return
        const act = a.action
        if (act.indexOf("focus:") === 0) aiFocus(act.slice(6))
        else if (act.indexOf("focuswin:") === 0) focusWindow(act.slice(9))
        else if (act === "clipboard") Globals.toggleClipboard()
        else if (act === "firewall") Globals.toggleFirewall()
        else if (act === "updates") Globals.toggleUpdates()
        else if (act === "aiusage") Globals.toggleAiUsage()
        else if (act === "disk") Globals.toggleDisk()
        else if (act === "logs") Globals.toggleLogs()
        else if (act.indexOf("folder:") === 0) {
            const f = act.slice(7)
            Quickshell.execDetached(["xdg-open", f.slice(0, f.lastIndexOf("/")) || "/"])
        }
    }

    // ── Toggles del sistema ─────────────────────────────────────────────────
    Connections {
        target: Globals
        function onDndChanged() {
            root.show({ icon: Globals.dnd ? "󰂛" : "󰂚", iconColor: Globals.dnd ? Theme.magenta : "white",
                        title: I18n.tr("Do Not Disturb"),
                        value: Globals.dnd ? I18n.tr("On") : I18n.tr("Off"),
                        valueColor: Globals.dnd ? Theme.magenta : Theme.fgMuted }, 2000)
        }
    }
    Connections {
        target: Settings
        function onCaffeineChanged() {
            if (!root._ready) return
            root.show({ icon: "󰅶", iconColor: Settings.caffeine ? Theme.yellow : "white",
                        title: I18n.tr("Caffeine"),
                        value: Settings.caffeine ? I18n.tr("On") : I18n.tr("Off"),
                        valueColor: Settings.caffeine ? Theme.yellow : Theme.fgMuted }, 2000)
        }
    }

    Timer {
        id: aiDemoStop
        property string agent: ""
        interval: 6000
        onTriggered: {
            if (agent === "") root.upd = null
            else root.aiEvent(agent, "stop", "demo-" + agent, "", "", "")
        }
    }

    IpcHandler {
        target: "island"
        function timer(duration: string): void { root.startTimer(root.parseDuration(duration)) }
        function stopwatch(): void { root.startStopwatch() }
        function pause(): void { root.togglePause() }
        function cancel(): void { root.cancelTimer() }
        function picker(): void { root.pickerOpen = !root.pickerOpen }
        function alert(title: string, value: string): void {
            root.show({ title: title, value: value, valueColor: Theme.accent }, 4000)
        }
        function dismiss(): void { root.dismiss() }
        // Responde a la pregunta visible (allow | always | block | kill …).
        function answer(choice: string): void { root.promptAnswer(choice) }
        function calendar(): void { if (!calProc.running) calProc.running = true }
        function aiEvent(agent: string, event: string, session: string, cwd: string, transcript: string, win: string): void {
            root.aiEvent(agent, event, session, cwd, transcript, win)
        }
        function screenshot(preview: string, path: string): void { root.showShot(preview, path) }
        // Pruebas: inyecta una línea como si viniera de /var/log/pacman.log.
        function pacmanLine(line: string): void { root._pacmanLine(line) }
        // Vista previa de avisos.
        // Abre el selector en la pestaña Alarm.
        function alarms(): void { root.pickerTab = "alarm"; root.alarmEdit = null; root.pickerOpen = true }
        function newAlarm(): void { root.pickerTab = "alarm"; root.pickerOpen = true; root.editAlarm(null) }
        function alarm(): void { Alarms._fire({ id: "demo", h: new Date().getHours(), m: new Date().getMinutes(), days: [], on: true, label: "Demo" }) }
        function demo(kind: string): void {
            const d = {
                battery: { title: I18n.tr("Low Battery"), value: "20%", valueColor: Theme.red, battery: 20 },
                critical: { title: I18n.tr("Critical Battery"), value: "5%", valueColor: Theme.red, battery: 5 },
                charging: { title: I18n.tr("Charging"), value: "75%", valueColor: Theme.green, battery: 75, charging: true },
                done: { icon: icons.timer, iconColor: Theme.orange, title: I18n.tr("Timer"),
                        value: I18n.tr("Done"), valueColor: Theme.orange },
                bt: { icon: icons.headphones, iconColor: Theme.accent, title: "AirPods Pro",
                      value: "80%", valueColor: Theme.green, battery: 80 },
                wifi: { icon: icons.wifi, iconColor: Theme.green, title: Net.ssid || "Home WiFi",
                        value: I18n.tr("Connected"), valueColor: Theme.green },
                vpn: { icon: icons.vpn, iconColor: Theme.green, title: "VPN",
                       value: I18n.tr("Connected"), valueColor: Theme.green },
                usage: { logo: "claude", title: "Claude · 5h", value: I18n.tr("%1% used").arg(90),
                         valueColor: Theme.red, action: "aiusage" },
                refresh: { logo: "claude", title: "Claude", value: I18n.tr("%1 limit refreshed").arg("5h"),
                           valueColor: Theme.green, action: "aiusage" },
                permission: { logo: "claude", title: "Claude", value: I18n.tr("Needs permission"),
                              valueColor: Theme.yellow },
                copy: { icon: icons.copy, iconColor: Theme.accent, title: I18n.tr("Copied"),
                        value: "sudo pacman -Syu --noconfirm", valueColor: Theme.fgMuted, action: "clipboard" },
                port: { icon: icons.alert, iconColor: Theme.yellow, title: I18n.tr("New open port"),
                        value: "TCP 8080 · python3", valueColor: Theme.yellow, action: "firewall" },
                updates: { icon: icons.pkg, iconColor: Theme.accent, title: I18n.tr("Updates available"),
                           value: I18n.tr("%1 packages").arg(12), valueColor: Theme.accent, action: "updates" },
                caps: { icon: icons.capslock, iconColor: Theme.accent, title: I18n.tr("Caps Lock"),
                        value: I18n.tr("On"), valueColor: Theme.accent },
                event: { icon: icons.calendar, iconColor: Theme.accent, title: "Team standup",
                         value: I18n.tr("in %1 min").arg(5), valueColor: Theme.accent }
            }[kind]
            if (kind === "usb") { root._usbPrompt(9001, "SanDisk Ultra", "storage", false, true); return }
            if (kind === "badusb") { root._usbPrompt(9002, "USB Keyboard", "keyboard", true, true); return }
            if (kind === "auth") { AuthWatch.failed("sudo", "playera", "pts/2", 2); return }
            if (kind === "away") { AuthWatch.awaySummary(3, []); return }
            if (kind === "intruder") { AuthWatch.awaySummary(3, [Wallpaper.isVideo(Wallpaper.current) ? Wallpaper.framePath(Wallpaper.current) : Wallpaper.current]); return }
            if (kind === "disk") { root._diskAlert(); return }
            if (kind === "mem") { root._memPrompt("warn", 1.4e9, "brave", 9.2e9, true); return }
            if (kind === "scan") {
                root._scanAlert({ src: "192.168.0.66", probed: 1000, proto: "TCP", type: "SYN", stealth: false,
                                  open: [{ port: 22, proto: "TCP" }, { port: 2222, proto: "TCP" }],
                                  closed: [{ port: 24800, proto: "TCP" }], filtered: new Array(997) }, true)
                return
            }
            if (kind === "ssh") { root._sshPrompt("192.168.0.66", "192.168.0.66", true); return }
            if (kind === "root") { root._rootPrompt("sudo", "192.168.0.66", true); return }
            if (kind === "brute") {
                root._bruteAlert({ key: "SSH|demo", service: "SSH", ip: "192.168.0.117", kind: "auth",
                                   count: 7, users: ["root", "admin"] }, true)
                return
            }
            if (kind === "brute-local") {
                root._bruteAlert({ key: "sudo|local", service: "sudo", ip: "", kind: "auth",
                                   count: 5, users: [Quickshell.env("USER")] }, true)
                return
            }
            if (kind === "banned") {
                const ip = "192.168.0.117"
                HostNames.lookup(ip)
                root._fwAlert({ kind: "banned", ip: ip, who: ip, service: "SSH", where: FwActivity.where(ip) })
                return
            }
            if (kind === "blocked") {
                const ip = "192.168.0.117"
                HostNames.lookup(ip)
                root._fwAlert({ kind: "blocked", ip: ip, who: ip, service: "UDP 39189", where: FwActivity.where(ip) })
                return
            }
            if (kind === "logout") { root._sshBye(Quickshell.env("USER"), "192.168.0.66"); return }
            if (kind === "activity") { root._fwAlert({ kind: "ssh", who: "192.168.0.66", where: "Home network", service: "SSH" }); return }
            if (kind === "download") { DownloadWatch.finished(DownloadWatch.dir + "/debian-13.7.0-amd64-netinst.iso"); return }
            if (kind === "crash") { CrashLog.unexpected({ status: "power" }); return }
            if (kind === "update") {
                root.upd = { phase: "install", done: 4, total: 12, pkg: "linux-firmware" }
                aiDemoStop.agent = ""
                aiDemoStop.restart()
                return
            }
            if (kind === "claude" || kind === "codex") {
                root.aiEvent(kind, "start", "demo-" + kind, "/home/demo/project", "", "")
                aiDemoStop.agent = kind
                aiDemoStop.restart()
                return
            }
            if (!d) return
            root.show(d, 5000)
            if (kind === "done") root.playDoneSound()
        }
    }
}
