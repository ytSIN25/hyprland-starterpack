import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Opens the GPU-offload apps menu.
IconPill {
    id: root
    interactive: true
    active: Globals.gpuOffloadOpen
    icon: "󰘚"   // md-chip
    iconColor: Globals.gpuOffloadOpen ? Theme.accent : Theme.fgDim
    badgeCount: GpuOffload.apps.filter(a => a.enabled).length
    badgeColor: Theme.accent
    onClicked: Globals.toggleGpuOffload()
}
