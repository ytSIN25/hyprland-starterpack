# Workstation mode — install guide (for an AI agent)

A Quickshell overlay for Hyprland. When toggled, the focused window shrinks
(live preview) into the lower part of the screen, and the other open windows
appear above it as live cards. Clicking a card focuses that window. With more
than 3 other windows the cards fan out into a stack, and the hovered card lifts,
scales up and gets an accent border. A visible scratchpad (special workspace)
is hidden on open, and scratchpad windows are never listed.

Triggers: **Ctrl+Super+Tab** and a **3-finger swipe up** on the touchpad.
Inside the overlay: click a card, or use Tab / arrow keys + Enter. Esc, clicking
the backdrop, clicking the shrunk window or toggling again goes back.

## Files in this package

```
INSTALL.md                                   ← this file
quickshell/Modules/Workstation/Workstation.qml   ← the whole feature (self-contained)
```

## Requirements — check these first

1. **Hyprland** (Lua config or classic `hyprland.conf`; both are supported).
2. **Quickshell 0.3+**: run `qs --version`. The module uses `Quickshell.Hyprland`,
   `ScreencopyView` (Quickshell.Wayland) and `ClippingRectangle` (Quickshell.Widgets).
3. **jq** and **hyprctl** on `PATH`: `which jq hyprctl`.
4. A running Quickshell config. Find it with `ls ~/.config/quickshell/`. The entry
   file is usually `shell.qml`. If the user runs a named config
   (`qs -c NAME`), it lives in `~/.config/quickshell/NAME/`.

Tell the user if something is missing instead of guessing.

## Step 1 — copy the module

Copy `quickshell/Modules/Workstation/` into the user's Quickshell config root,
keeping the folder layout:

```sh
CFG=~/.config/quickshell            # adjust if the user uses a named config
mkdir -p "$CFG/Modules"
cp -r quickshell/Modules/Workstation "$CFG/Modules/"
```

If `$CFG/Modules/Workstation` already exists, back it up first
(e.g. `mv … Workstation.bak`). Never overwrite without a backup.

## Step 2 — instantiate it in the shell entry file

Back up `shell.qml` (`cp shell.qml shell.qml.pre-workstation`), then:

1. Add the import next to the other imports:
   ```qml
   import qs.Modules.Workstation
   ```
2. Add one instance **directly inside the root `ShellRoot { … }`**, not inside a
   `Variants`/per-screen delegate (it picks the focused monitor itself):
   ```qml
   Workstation {}
   ```

Optional: match the user's theme by setting properties on the instance, e.g.
```qml
Workstation {
    accent: Theme.accent          // only if such a theme singleton exists
    surface: Theme.surface
    fontFamily: Theme.fontFamily
    // stackThreshold: 3   // more windows than this → stacked fan
    // splitRatio: 0.4     // top/bottom split; lower = bigger main window
    // topInset: 64        // space kept free at the top for the bar
}
```
Only reference properties you have confirmed exist in the user's config.
If the config has a central "close all panels" signal, you may connect it to
`close()` on the instance; this is optional.

Quickshell hot-reloads on save. Check the log for errors:
`qs log | tail -30` (look for lines mentioning `Workstation`).

## Step 3 — keybind and gesture

Detect the config style: if `~/.config/hypr/hyprland.lua` exists, the user is on
the **Lua** config; otherwise it's the classic **hyprland.conf**. Find the
file where the other binds / gestures live (`grep -rn "bind" ~/.config/hypr`)
and back it up before editing.

**Lua config:**
```lua
-- Workstation mode
hl.bind("CTRL + SUPER + TAB", hl.dsp.exec_cmd("qs ipc call workstation toggle"))

-- 3-finger swipe up: workstation mode
hl.gesture({
    fingers = 3,
    direction = "up",
    action = function() hl.exec_cmd("qs ipc call workstation toggle") end
})
```

**Classic hyprland.conf:**
```ini
# Workstation mode
bind = CTRL SUPER, Tab, exec, qs ipc call workstation toggle

# 3-finger swipe up: workstation mode (needs Hyprland ≥ 0.51 gesture syntax)
gesture = 3, up, dispatcher, exec, qs ipc call workstation toggle
```

If the user runs a named Quickshell config, the IPC call needs it too:
`qs -c NAME ipc call workstation toggle`.

Before adding, check for conflicts: `grep -rn -i "SUPER.*TAB\|gesture" ~/.config/hypr`.
If Ctrl+Super+Tab or a 3-finger vertical gesture is already bound, ask the user
which to keep. A 3-finger **horizontal** workspace swipe does not conflict.

Then reload and check for errors:
```sh
hyprctl reload
hyprctl configerrors     # must print nothing / "ok"
```

## Step 4 — verify

1. `qs ipc call workstation toggle`: the overlay should appear on the focused
   monitor with the current window shrinking to the bottom. Take a screenshot
   (`grim`) if you can view images.
2. `qs ipc call workstation hide`: closes it.
3. Ask the user to try a real click on a card, the hover effect, Ctrl+Super+Tab
   and the 3-finger swipe; these need real input.

## Troubleshooting

- **`module "qs.Modules.Workstation" is not installed`**: the folder isn't at
  `<config root>/Modules/Workstation/`, or the import path doesn't match.
- **Cards are blank / only show an icon**: the compositor isn't exposing
  toplevel capture to Quickshell; update Hyprland and Quickshell.
- **Clicking a card doesn't switch**: run
  `hyprctl dispatch focuswindow address:0x<addr>` (classic) or
  `hyprctl dispatch 'hl.dsp.focus({ window = "address:0x<addr>" })'` (Lua) by hand
  to confirm the dispatcher works on this Hyprland version.
- **Overlay covers the bar badly**: adjust `topInset`.

## Uninstall

Remove `Workstation {}` and its import from `shell.qml`, delete
`Modules/Workstation/`, and remove the bind and gesture lines; or restore the
`.pre-workstation` backups.
