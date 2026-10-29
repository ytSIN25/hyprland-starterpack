import QtQuick
import qs.Components
import qs.Config

// Botón de apagado. Requiere confirmación: el primer click lo "arma" (se pone
// rojo) y solo un segundo click en los 3 s siguientes apaga el equipo, para
// evitar apagados accidentales (p. ej. por VNC con lag).
IconPill {
    id: root
    interactive: true
    icon: "󰐥"
    iconColor: armed ? Theme.red : Theme.fgMuted
    animateColor: true
    active: armed

    property bool armed: false

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = false
    }

    onClicked: {
        if (armed) {
            disarm.stop()
            armed = false
            Globals.runPowerAction("poweroff")
        } else {
            armed = true
            disarm.restart()
        }
    }
    onRightClicked: { disarm.stop(); armed = false }
}
