#!/usr/bin/env bash
# Starter pack installer: Hyprland + Quickshell desktop for an existing Arch install.
#
#   ./install.sh               install packages, then the dotfiles
#   ./install.sh -y            same, accept all defaults (no questions)
#   ./install.sh --no-packages only (re)copy the dotfiles
#   ./install.sh --brand asus  also install the extra packages for that laptop brand
#                              (asus, lenovo-legion, thinkpad, framework, dell, msi,
#                               acer, nvidia-hybrid, none)
#
# Existing configs that would be overwritten are moved to
# ~/.config/starterpack-backup-<date>/ first. Nothing is deleted.

set -euo pipefail

PACK="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP="$CFG/starterpack-backup-$(date +%Y%m%d-%H%M%S)"
GUIDE_DIR="$CFG/starterpack"

ASSUME_YES=0
DO_PACKAGES=1
BRAND=""

# ---------------------------------------------------------------------------
# Packages
# ---------------------------------------------------------------------------

PKGS_CORE=(
    # compositor, lock, idle, portals
    hyprland hyprlock hypridle hyprpicker hyprpolkitagent
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk polkit
    # shell / bar / launcher / wallpaper
    quickshell qt6-multimedia qt6-5compat qt6-svg qt6-imageformats
    rofi awww
    # terminal + shell
    kitty fish starship eza btop
    # apps used by the binds
    nautilus
    # audio, media, brightness
    pipewire pipewire-pulse wireplumber playerctl brightnessctl ddcutil
    # screenshots, recording, clipboard
    grim slurp hyprshot gpu-screen-recorder ffmpeg wl-clipboard cliphist wtype imagemagick
    # network, bluetooth, power
    networkmanager bluez bluez-utils power-profiles-daemon upower iproute2 iw
    # laptop audio firmware (most Intel/AMD laptops since ~2019)
    sof-firmware
    # helpers the shell scripts call
    jq curl libnotify python python-yaml xdg-user-dirs xdg-utils
    # theming
    qt6ct nwg-look
    # input method (Chinese / Korean / etc.)
    fcitx5 fcitx5-gtk fcitx5-qt fcitx5-configtool
    # fonts
    ttf-jetbrains-mono-nerd inter-font noto-fonts noto-fonts-cjk noto-fonts-emoji
)

PKGS_AUR=(
    wlogout     # power menu
    ttfx        # screensaver text effects (optional, skipped if the build fails)
)

# DKMS modules need the headers of every installed kernel
kernel_headers() {
    local k out=""
    for k in linux linux-lts linux-zen linux-hardened; do
        pacman -Qq "$k" >/dev/null 2>&1 && out+="$k-headers "
    done
    echo "${out:-linux-headers}"
}

brand_packages() {
    case "$1" in
        asus)          echo "asusctl rog-control-center supergfxctl" ;;
        lenovo-legion) echo "$(kernel_headers) lenovolegionlinux-dkms-git lenovolegionlinux-git" ;;
        thinkpad)      echo "fprintd acpi_call-dkms $(kernel_headers)" ;;
        framework)     echo "framework-system fprintd iio-sensor-proxy" ;;
        dell)          echo "thermald dell-command-configure" ;;
        msi)           echo "isw" ;;
        acer)          echo "nbfc-linux" ;;
        nvidia-hybrid) echo "$(kernel_headers) nvidia-open-dkms nvidia-utils nvidia-prime" ;;
        none|"")       echo "" ;;
        *) die "unknown brand '$1'" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

c_info=$'\e[1;34m'; c_ok=$'\e[1;32m'; c_warn=$'\e[1;33m'; c_err=$'\e[1;31m'; c_off=$'\e[0m'
info() { printf '%s::%s %s\n' "$c_info" "$c_off" "$*"; }
ok()   { printf '%s✓%s %s\n'  "$c_ok"   "$c_off" "$*"; }
warn() { printf '%s!%s %s\n'  "$c_warn" "$c_off" "$*"; }
die()  { printf '%s✗%s %s\n'  "$c_err"  "$c_off" "$*" >&2; exit 1; }

ask() {  # ask "question" default(y/n)
    local def="$2" reply
    if ((ASSUME_YES)); then [[ $def == y ]]; return; fi
    read -rp "$1 [$( [[ $def == y ]] && echo Y/n || echo y/N )] " reply
    reply="${reply:-$def}"
    [[ ${reply,,} == y* ]]
}

aur() { yay -S --needed --noconfirm "$@"; }

# ---------------------------------------------------------------------------
# Arguments + sanity checks
# ---------------------------------------------------------------------------

while (($#)); do
    case "$1" in
        -y|--yes)      ASSUME_YES=1 ;;
        --no-packages) DO_PACKAGES=0 ;;
        --brand)       BRAND="${2:-}"; shift ;;
        --brand=*)     BRAND="${1#*=}" ;;
        -h|--help)     sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

[[ $EUID -ne 0 ]] || die "run as your normal user, not root (sudo is used when needed)"
[[ -f /etc/arch-release ]] || warn "this does not look like Arch Linux; continuing anyway"
[[ -d "$PACK/config" ]] || die "config/ not found next to install.sh"
[[ -n $BRAND ]] && brand_packages "$BRAND" >/dev/null

echo
info "Starter pack installer"
echo "   pack:    $PACK"
echo "   target:  $HOME"
echo

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------

if ((DO_PACKAGES)); then
    command -v sudo >/dev/null || die "sudo is required"
    sudo -v

    info "Updating system and installing packages (pacman)"
    pkgs=("${PKGS_CORE[@]}")
    # A browser is needed to show the guide; add one only if none is installed
    have_browser=0
    for b in firefox chromium brave google-chrome-stable vivaldi zen-browser librewolf; do
        command -v "$b" >/dev/null && have_browser=1
    done
    ((have_browser)) || pkgs+=(firefox)
    sudo pacman -Syu --needed --noconfirm "${pkgs[@]}"
    ok "official packages installed"

    if ! command -v yay >/dev/null && ! command -v paru >/dev/null; then
        info "Installing yay (AUR helper)"
        sudo pacman -S --needed --noconfirm git base-devel
        tmp="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    command -v yay >/dev/null || aur() { paru -S --needed --noconfirm "$@"; }

    info "Installing AUR packages"
    for p in "${PKGS_AUR[@]}"; do
        aur "$p" || warn "could not install $p (AUR) — skipping"
    done

    if [[ -z $BRAND ]] && ((!ASSUME_YES)); then
        echo
        echo "Optional laptop extras: asus, lenovo-legion, thinkpad, framework, dell, msi, acer, nvidia-hybrid"
        read -rp "Laptop brand extras to install (Enter = none): " BRAND
        brand_packages "${BRAND:-none}" >/dev/null
    fi
    if [[ -n $BRAND && $BRAND != none ]]; then
        info "Installing extras for $BRAND"
        for p in $(brand_packages "$BRAND"); do
            aur "$p" || warn "could not install $p — skipping"
        done
        case "$BRAND" in
            asus)          sudo systemctl enable --now supergfxd 2>/dev/null || true ;;
            dell)          sudo systemctl enable --now thermald 2>/dev/null || true ;;
            nvidia-hybrid) warn "reboot after install so the NVIDIA driver loads" ;;
        esac
    fi

    info "Enabling services"
    sudo systemctl enable --now NetworkManager.service      || warn "NetworkManager not enabled"
    sudo systemctl enable --now bluetooth.service           || warn "bluetooth not enabled"
    sudo systemctl enable --now power-profiles-daemon.service \
        || warn "power-profiles-daemon not enabled (tlp installed? they conflict)"
    systemctl --user enable --now pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
    ok "services enabled"
fi

# ---------------------------------------------------------------------------
# 2. Dotfiles
# ---------------------------------------------------------------------------

info "Copying configs to $CFG (old ones go to $BACKUP)"
mkdir -p "$CFG" "$HOME/.local/bin" "$HOME/.local/share/icons"

backup() {  # backup <path relative to $HOME>
    local src="$HOME/$1"
    [[ -e $src || -L $src ]] || return 0
    mkdir -p "$BACKUP/$(dirname "$1")"
    mv "$src" "$BACKUP/$1"
}

for item in "$PACK"/config/*; do
    name="$(basename "$item")"
    rel="${CFG#"$HOME"/}/$name"
    if [[ $name == wallpapers && -d "$CFG/wallpapers" ]]; then
        # Merge wallpapers instead of replacing the user's collection
        cp -rn "$item/." "$CFG/wallpapers/"
        continue
    fi
    backup "$rel"
    cp -r "$item" "$CFG/$name"
done

for f in "$PACK"/local/bin/*; do
    backup ".local/bin/$(basename "$f")"
    install -m 755 "$f" "$HOME/.local/bin/"
done

backup ".local/share/icons/Keqing"
cp -r "$PACK/local/share/icons/Keqing" "$HOME/.local/share/icons/"
mkdir -p "$HOME/.local/share/icons/default"
printf '[Icon Theme]\nInherits=Keqing\n' > "$HOME/.local/share/icons/default/index.theme"

[[ -e $HOME/.face ]] || cp "$PACK/local/face.png" "$HOME/.face"

# SDDM login theme sources (installed into SDDM only if asked below)
backup "${CFG#"$HOME"/}/sddm-launcher"
cp -r "$PACK/extras/sddm-launcher" "$CFG/sddm-launcher"
chmod +x "$CFG/sddm-launcher/install.sh"

# Fill in the user's home and name where the configs need absolute paths
grep -rlI --exclude-dir=wallpapers -e '@HOME@' -e '@USER@' \
    "$CFG"/{hypr,quickshell,gtk-3.0} 2>/dev/null \
    | xargs -r sed -i "s|@HOME@|$HOME|g; s|@USER@|$USER|g"

# Default wallpaper: first one found, else hyprlock blurs a screenshot instead
wall="$(find "$CFG/wallpapers" "$HOME/Pictures/Wallpapers" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | sort | head -1 || true)"
if [[ -n $wall ]]; then
    sed -i "s|@WALLPAPER@|$wall|" "$CFG/hypr/hyprlock.conf" "$CFG/quickshell/settings.json"
else
    sed -i 's|@WALLPAPER@|screenshot|; s|blur_passes = 0|blur_passes = 3|; s|blur_size = 1$|blur_size = 8|' \
        "$CFG/hypr/hyprlock.conf"
    sed -i 's|"@WALLPAPER@"|""|' "$CFG/quickshell/settings.json"
    warn "no wallpapers found: add some to ~/Pictures/Wallpapers, then press Super+W"
fi

chmod +x "$CFG"/screensaver/*.sh "$CFG"/rofi/type-2/launcher.sh "$CFG"/rofi/bin/* \
         "$CFG"/quickshell/scripts/* 2>/dev/null || true

command -v xdg-user-dirs-update >/dev/null && xdg-user-dirs-update
mkdir -p "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Screenshots" "$HOME/Videos"
command -v fc-cache >/dev/null && fc-cache -f >/dev/null
ok "configs installed"

# ---------------------------------------------------------------------------
# 3. Optional bits that need root
# ---------------------------------------------------------------------------

if ((DO_PACKAGES)); then
    if [[ ${SHELL##*/} != fish ]] && ask "Make fish your default shell?" y; then
        chsh -s "$(command -v fish)" || warn "chsh failed; run: chsh -s /usr/bin/fish"
    fi

    if ask "Install SDDM with the matching login theme (graphical login screen)?" n; then
        sudo pacman -S --needed --noconfirm sddm qt6-declarative
        sudo "$CFG/sddm-launcher/install.sh"
        if ! systemctl is-enabled --quiet display-manager.service 2>/dev/null; then
            sudo systemctl enable sddm.service
        else
            warn "another display manager is enabled; switch with: sudo systemctl enable -f sddm"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 4. Guide
# ---------------------------------------------------------------------------

mkdir -p "$GUIDE_DIR"
cp "$PACK/guide.html" "$GUIDE_DIR/guide.html"
cp -r "$PACK/extras" "$GUIDE_DIR/"
grep -rlI -e '@HOME@' -e '@USER@' "$GUIDE_DIR/extras" \
    | xargs -r sed -i "s|@HOME@|$HOME|g; s|@USER@|$USER|g"

echo
ok "Done. Backups of replaced files: $BACKUP"
echo "   Guide: $GUIDE_DIR/guide.html"

if [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && command -v xdg-open >/dev/null; then
    (setsid xdg-open "$GUIDE_DIR/guide.html" >/dev/null 2>&1 &)
else
    # No desktop yet (installed from a TTY): open it on the first Hyprland login
    touch "$GUIDE_DIR/show-guide"
    echo "   Start Hyprland (type: Hyprland) — the guide opens on first login."
fi
