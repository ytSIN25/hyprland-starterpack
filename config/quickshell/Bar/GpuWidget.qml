import QtQuick
import qs.Components
import qs.Config
import qs.Services

// GPU (nvidia-smi, vía SysMon.gpuBusy/gpuTemp). Oculto si no hay lectura
// (gpuBusy < 0), igual que la tarjeta del panel de Recursos. Click abre el
// monitor de sistema, mismo comportamiento que SysMonWidget.
Pill {
    id: root
    interactive: true
    active: Globals.sysMonOpen
    onClicked: Globals.toggleSysMon()

    Text {
        text: "󰢮"
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    Text {
        text: Math.round(SysMon.gpuBusy) + "%"
        color: SysMon.gpuBusy >= 97 ? Theme.red
             : SysMon.gpuBusy >= 90 ? Theme.yellow
             : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
