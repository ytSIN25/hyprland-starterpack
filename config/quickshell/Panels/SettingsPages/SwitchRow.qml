import QtQuick
import QtQuick.Layouts
import qs.Components
import qs.Config
import qs.Panels.SettingsPages

// Fila con etiqueta (y descripción opcional) + interruptor a la derecha. La
// fila ENTERA es el área de toque (clic en cualquier punto la activa, no solo
// la bolita) y se resalta sutilmente al pasar el ratón: el panel entero
// comparte así el mismo lenguaje táctil que la nav.
//
// Root es un Item, no un RowLayout: así puede haber un fondo de hover DETRÁS
// del contenido sin que la fila intente gestionarlo como si fuera otro campo
// de la columna. Los consumidores («SwitchRow { Layout.fillWidth: ... }» en
// cada página) no notan el cambio: Layout.fillWidth funciona igual sobre
// cualquier Item.
Item {
    id: sr
    property string label: ""
    property string desc: ""
    property bool checked: false
    signal toggled()
    // Widgets de la barra: objectName del widget. Si se da, aparece la píldora
    // "Hidden" (oculto: solo se ve con SUPER+SHIFT+D).
    property string hideKey: ""

    // Filtro de la ventana de Ajustes (buscador + "solo modificados").
    // OPT-IN: sin 'skey' la fila no se filtra nunca, así el mismo componente
    // sigue funcionando fuera de Ajustes. 'shown' es la condición propia de la
    // página (p. ej. "solo si hay batería"), que se combina con el filtro.
    property string skey: ""
    property string cardTitle: ""
    property bool shown: true
    readonly property bool matches: SettingsFilter.accepts(
        sr.label + " " + sr.desc + " " + sr.cardTitle, sr.skey)
    visible: sr.shown && sr.matches

    Layout.fillWidth: true
    implicitHeight: Math.max(row.implicitHeight, Theme.dp(36))

    // Fondo de hover: solo opacidad, sin color propio, para no imponer un tono
    // que desentone con el tema activo. Sangra un poco fuera del alto de la
    // fila para que la franja realzada respire, sin invadir la fila vecina
    // (el hueco entre filas, Theme.space14 en las páginas, es mayor que esto).
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Theme.space6
        radius: Theme.dp(8)
        color: SettingsPalette.settingsHover
        opacity: rowMa.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animFast; easing.type: Easing.OutQuad } }
    }

    // Área de toque de la fila entera. Va ANTES del contenido (más abajo en
    // el orden de apilado): el interruptor, dibujado después, sigue captando
    // sus propios clics con prioridad; el resto de la fila cae aquí.
    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sr.toggled()
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space10
        ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Text {
                Layout.fillWidth: true
                text: sr.label; color: Theme.fg
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
            }
            Text {
                Layout.fillWidth: true
                visible: sr.desc !== ""
                text: sr.desc; color: Theme.fgMuted
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                wrapMode: Text.WordWrap
            }
        }
        Rectangle {
            id: hidePill
            visible: sr.hideKey !== ""
            readonly property bool on: sr.hideKey !== "" && Settings.isWidgetHidden(sr.hideKey)
            opacity: sr.checked ? 1 : 0.4
            implicitWidth: hideRow.implicitWidth + Theme.space10 * 2
            implicitHeight: Theme.dp(24)
            radius: height / 2
            color: on ? Theme.withAlpha(Theme.accent, 0.2) : (hideMa.containsMouse ? SettingsPalette.settingsHover : "transparent")
            border.width: Theme.hairline
            border.color: on ? Theme.withAlpha(Theme.accent, 0.6) : SettingsPalette.settingsBorder
            Behavior on color { ColorAnimation { duration: Theme.animFast } }
            Row {
                id: hideRow
                anchors.centerIn: parent
                spacing: Theme.space4
                Text {
                    text: hidePill.on ? "󰈉" : "󰈈"
                    color: hidePill.on ? Theme.accent : Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                }
                Text {
                    text: hidePill.on ? I18n.tr("Hidden") : I18n.tr("Shown")
                    color: hidePill.on ? Theme.accent : Theme.fgMuted
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 3
                }
            }
            MouseArea {
                id: hideMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Settings.setWidgetHidden(sr.hideKey, !hidePill.on)
            }
        }
        Switch {
            checked: sr.checked
            offColor: SettingsPalette.settingsControl
            offBorderColor: SettingsPalette.settingsBorder
            onToggled: sr.toggled()
        }
    }
}
