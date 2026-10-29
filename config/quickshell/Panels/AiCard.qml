import QtQuick
import QtQuick.Layouts
import qs.Config

// Rounded card for AiUsagePanel; children stack in a padded column.
Rectangle {
    default property alias content: cardCol.data
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredWidth: 1     // equal columns in the grid
    implicitHeight: cardCol.implicitHeight + Theme.dp(16) * 2
    radius: Theme.dp(16)
    color: Theme.surface
    ColumnLayout {
        id: cardCol
        anchors.fill: parent
        anchors.margins: Theme.dp(16)
        spacing: Theme.dp(8)
    }
}
