import QtQuick
import qs.Components
import qs.Config
import qs.Services

// Abre el limpiador de disco. En rojo si queda poco espacio.
IconPill {
    id: root
    interactive: true
    active: Globals.diskOpen
    icon: "\u{f02ca}"   // md-harddisk
    iconColor: DiskClean.lowSpace ? Theme.red : Theme.fgDim
    onClicked: Globals.toggleDisk()
}
