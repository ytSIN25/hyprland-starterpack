pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Forces specific apps to always launch on the dedicated GPU instead of
// relying on Optimus/the driver to pick correctly (which is what fails
// intermittently). Mechanism: for each enabled app, write a user-level
// .desktop override in ~/.local/share/applications/ that wraps the app's
// original Exec= with NVIDIA PRIME render-offload env vars. Disabling
// writes the opposite override, pinning the app to the Intel iGPU's Mesa
// GL/EGL vendor: left to defaults, X11/XWayland clients (and Chromium with
// --ozone-platform=x11 in a *-flags.conf) still land on NVIDIA, because
// libglvnd tries 10_nvidia.json before 50_mesa.json. Removing an app from
// the list deletes the override, so the system .desktop takes over again.
//
// Only the PRIME env vars are used. Forcing a Wayland client onto the NVIDIA
// render node directly (e.g. Chromium's --render-node-override) hands
// cross-GPU buffers to Hyprland, which renders on the Intel iGPU, and
// crashed the compositor — don't add that here.
Singleton {
    id: gpu

    // [{ id, name, icon, enabled }]
    readonly property var apps: Settings.gpuOffloadApps

    function isTracked(id) {
        return gpu.apps.some(a => a.id === id)
    }

    function addApp(entry) {
        if (!entry || !entry.id || gpu.isTracked(entry.id)) return
        const list = gpu.apps.slice()
        list.push({ id: entry.id, name: entry.name ?? entry.id, icon: entry.icon ?? "", enabled: false })
        Settings.gpuOffloadApps = list
    }

    function removeApp(id) {
        Settings.gpuOffloadApps = gpu.apps.filter(a => a.id !== id)
        gpu._run(gpu._disableScript(), [id])
    }

    function setEnabled(id, on) {
        const list = gpu.apps.slice()
        const i = list.findIndex(a => a.id === id)
        if (i === -1) return
        list[i] = Object.assign({}, list[i], { enabled: on })
        Settings.gpuOffloadApps = list
        gpu._run(gpu._writeScript(on), [id])
    }

    // Overrides are only written when a toggle flips, so after a reinstall
    // (or when a package update replaces the system .desktop) an app could
    // show ON while launching without offload. Rebuild them all at startup.
    function syncAll() {
        const loop = "s=$1; shift; for id in \"$@\"; do sh -c \"$s\" _ \"$id\" || true; done"
        const on = gpu.apps.filter(a => a.enabled).map(a => a.id)
        const off = gpu.apps.filter(a => !a.enabled).map(a => a.id)
        if (on.length) Quickshell.execDetached(["sh", "-c", loop, "_", gpu._writeScript(true)].concat(on))
        if (off.length) Quickshell.execDetached(["sh", "-c", loop, "_", gpu._writeScript(false)].concat(off))
    }

    Timer {
        // Settings load asynchronously; wait until they're in.
        interval: 500
        repeat: true
        running: true
        onTriggered: if (Settings._loaded) { stop(); gpu.syncAll() }
    }

    // NVIDIA PRIME render offload (Optimus, Wayland). If your machine is
    // AMD/Intel muxless instead, replace these with "DRI_PRIME=1".
    readonly property var _vars: [
        "__NV_PRIME_RENDER_OFFLOAD=1",
        "__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0",
        "__GLX_VENDOR_LIBRARY_NAME=nvidia",
        "__VK_LAYER_NV_optimus=NVIDIA_only"
    ]

    // OFF: pin GL/EGL to Mesa (the iGPU). Vulkan can only follow if an Intel
    // Vulkan driver (vulkan-intel) is installed; the NV layer then hides the dGPU.
    readonly property var _igpuVars: [
        "__GLX_VENDOR_LIBRARY_NAME=mesa",
        "__EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json",
        "__VK_LAYER_NV_optimus=non_NVIDIA_only"
    ]

    // Shared shell prelude: $id, override path, and where a user-installed
    // .desktop (AppImages etc.) is backed up before being rewritten in place.
    readonly property string _prelude: [
        "id=\"$1\"",
        "apps=\"$HOME/.local/share/applications\"",
        "dst=\"$apps/$id.desktop\"",
        "orig=\"$HOME/.local/share/quickshell/gpu-offload/$id.desktop\""
    ].join("\n")

    // Chromium, Electron and CEF apps render on the iGPU under Wayland no
    // matter what the PRIME vars say. Under XWayland (--ozone-platform=x11)
    // they honour them and the NVIDIA driver hands frames to Hyprland safely.
    readonly property string _detectFn: String.raw`
is_chromium_app() {
    b=$(command -v "$1" 2>/dev/null || printf '%s' "$1"); b=$(readlink -f "$b" 2>/dev/null) || return 1
    [ -f "$b" ] || return 1
    case "$(basename "$b")" in *chrom*|brave*|vivaldi*|opera*|*edge*|electron*) return 0 ;; esac
    has_pak() { d=$(dirname "$1"); [ -e "$d/resources.pak" ] || [ -e "$d/v8_context_snapshot.bin" ] || [ -e "$d/libcef.so" ]; }
    has_pak "$b" && return 0
    if ! head -c4 "$b" | grep -q ELF; then
        grep -qE '(^|[^a-z])electron[0-9]*([^a-z]|$)' "$b" && return 0
        for p in $(grep -oE '/[A-Za-z0-9._/-]+' "$b" | sort -u); do
            [ -f "$p" ] && [ -x "$p" ] && has_pak "$p" && return 0
        done
    fi
    return 1
}`

    // Finds the app's .desktop, prefixes every Exec= line with the offload
    // (on) or iGPU (off) vars (as --env= flags for Flatpak, whose sandbox
    // drops host env) and saves the result as a marked user override. Field
    // codes (%U, %F…) are kept so files/links opened with the app still reach it.
    function _writeScript(on) {
        const vars = on ? gpu._vars : gpu._igpuVars
        const envPrefix = "env " + vars.join(" ") + " "
        const flatpakEnv = vars.map(v => "--env=" + v).join(" ") + " "
        return [
            "set -e",
            gpu._prelude,
            "src=$(find /usr/share/applications /usr/local/share/applications " +
                "/var/lib/flatpak/exports/share/applications " +
                "\"$HOME/.local/share/flatpak/exports/share/applications\" " +
                "-maxdepth 3 -iname \"$id.desktop\" 2>/dev/null | head -n1)",
            // No system copy: it's a user-installed app. Back up the original
            // once (never our own override) and build from the backup.
            "if [ -z \"$src\" ]; then",
            "  if [ -f \"$dst\" ] && ! grep -q '^X-GpuOffload=true' \"$dst\"; then",
            "    mkdir -p \"$(dirname \"$orig\")\"; cp \"$dst\" \"$orig\"",
            "  fi",
            "  [ -f \"$orig\" ] || exit 1",
            "  src=\"$orig\"",
            "fi",
            gpu._detectFn,
            "bin=$(sed -n 's/^Exec=//p' \"$src\" | head -n1 | awk '{print $1}' | tr -d '\"')",
            "xf=\"\"",
            on ? "case \"$bin\" in *flatpak) ;; *) is_chromium_app \"$bin\" && xf=\"--ozone-platform=x11\" ;; esac" : "",
            "mkdir -p \"$apps\"",
            "tmp=$(mktemp \"$apps/.gpu-offload.XXXXXX\")",
            "awk -v pre='" + envPrefix + "' -v fp='" + flatpakEnv + "' -v xf=\"$xf\" '" +
                "/^X-GpuOffload=/ { next } " +
                "/^Exec=/ { cmd = substr($0, 6); " +
                    "if (xf != \"\" && cmd !~ /--ozone-platform=/) { " +
                        "n = index(cmd, \" \"); cmd = n ? substr(cmd, 1, n) xf \" \" substr(cmd, n + 1) : cmd \" \" xf } " +
                    "if (cmd ~ /(^|\\/)flatpak run /) sub(/flatpak run /, \"flatpak run \" fp, cmd); " +
                    "else if (cmd !~ /__NV_PRIME_RENDER_OFFLOAD=|__GLX_VENDOR_LIBRARY_NAME=mesa/) cmd = pre cmd; " +
                    "print \"Exec=\" cmd; next } " +
                "{ print } " +
                "/^\\[Desktop Entry\\]/ { print \"X-GpuOffload=true\" }' \"$src\" > \"$tmp\"",
            "mv \"$tmp\" \"$dst\"",
            "update-desktop-database \"$apps\" 2>/dev/null || true"
        ].join("\n")
    }

    // Restores a backed-up user .desktop, or removes our override. Never
    // deletes a .desktop we didn't write.
    function _disableScript() {
        return [
            gpu._prelude,
            "if [ -f \"$orig\" ]; then mv \"$orig\" \"$dst\"",
            "elif [ -f \"$dst\" ] && grep -q '^X-GpuOffload=true' \"$dst\"; then rm -f \"$dst\"",
            // Overrides from the older version of this service had no marker
            // but always wrapped Exec= with the PRIME vars.
            "elif [ -f \"$dst\" ] && grep -q '^Exec=env __NV_PRIME_RENDER_OFFLOAD=1' \"$dst\"; then rm -f \"$dst\"; fi",
            "update-desktop-database \"$apps\" 2>/dev/null || true"
        ].join("\n")
    }

    // Detached, one process per call: a shared Process ignores a new command
    // while the previous toggle's script is still running.
    function _run(script, args) {
        Quickshell.execDetached(["sh", "-c", script, "_"].concat(args))
    }
}
