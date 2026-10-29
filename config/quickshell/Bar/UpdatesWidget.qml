import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Opens the pending-updates menu (pacman/AUR/Flatpak).
IconPill {
    id: root
    interactive: true
    active: Globals.updatesOpen
    icon: "󰏖"   // md-package_variant
    iconColor: PackageUpdates.count > 0 ? Theme.accent : Theme.fgDim
    badgeCount: PackageUpdates.count
    badgeColor: Theme.accent
    onClicked: Globals.toggleUpdates()
}
