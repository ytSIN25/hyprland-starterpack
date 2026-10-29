# Starter Pack

Hyprland + Quickshell desktop for an existing Arch Linux install.

```bash
./install.sh            # packages + configs (asks a few questions)
./install.sh -y         # same, no questions
./install.sh --no-packages          # only copy the configs
./install.sh --brand asus           # also laptop extras: asus, lenovo-legion,
                                    # thinkpad, framework, dell, msi, acer, nvidia-hybrid
```

No wallpapers are included: drop your own into `config/wallpapers/` before
installing, or into `~/Pictures/Wallpapers/` afterwards.

Replaced configs are moved to `~/.config/starterpack-backup-<date>/`.
When it finishes, `guide.html` opens (keybinds, wallpapers, laptop extras).
Installed from a TTY? It opens on the first Hyprland login instead.

| Folder     | Goes to                     |
|------------|-----------------------------|
| `config/`  | `~/.config/`                |
| `local/`   | `~/.local/` (cursor, picker script), `~/.face` |
| `extras/`  | `~/.config/starterpack/extras/`, not enabled by default: firewall, workstation mode, Waybar/SwayNC |
