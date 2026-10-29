import QtQuick
import qs.Config
import qs.Components
import qs.Services

// Logo de la distro. Solo decorativo: el lanzador de apps (AppLauncher) se
// quitó; las apps se abren con rofi desde su atajo de Hyprland.
Pill {
    id: root

    Text {
        text: SysMon.distroGlyph
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.barIconSize + 3
    }
}
