import QtQuick
import qs.Components
import qs.Config
import qs.Services

// CPU y RAM. Click abre el monitor de sistema.
Pill {
    id: root
    interactive: true
    active: Globals.sysMonOpen
    onClicked: Globals.toggleSysMon()

    Text {
        text: "󰻠"   // cpu
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    // Los porcentajes avisan por color al acercarse al límite (90% ámbar,
    // 97% rojo), sin cambiar de tamaño ni mover la píldora.
    Text {
        text: Math.round(SysMon.cpu) + "%"
        color: SysMon.cpu >= 97 ? Theme.red
             : SysMon.cpu >= 90 ? Theme.yellow
             : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    Rectangle {
        implicitWidth: Theme.barVertical ? Theme.dp(14) : Theme.hairline
        implicitHeight: Theme.barVertical ? Theme.hairline : Theme.dp(14)
        color: Theme.overlay
    }
    Text {
        text: "󰍛"   // ram
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    Text {
        text: Math.round(SysMon.memPercent) + "%"
        color: SysMon.memPercent >= 97 ? Theme.red
             : SysMon.memPercent >= 90 ? Theme.yellow
             : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
    // GPU (nvidia-smi): oculto entero -- separador incluido -- si no hay
    // lectura (gpuBusy < 0), en vez de mostrar un tercer bloque vacío.
    Rectangle {
        visible: SysMon.gpuBusy >= 0
        implicitWidth: Theme.barVertical ? Theme.dp(14) : Theme.hairline
        implicitHeight: Theme.barVertical ? Theme.hairline : Theme.dp(14)
        color: Theme.overlay
    }
    Text {
        visible: SysMon.gpuBusy >= 0
        text: "󰢮"   // gpu (nf-md-expansion_card)
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize
    }
    Text {
        visible: SysMon.gpuBusy >= 0
        text: Math.round(SysMon.gpuBusy) + "%"
        color: SysMon.gpuBusy >= 97 ? Theme.red
             : SysMon.gpuBusy >= 90 ? Theme.yellow
             : Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Behavior on color { ColorAnimation { duration: Theme.animFast } }
    }
}
