import QtQuick
import QtQuick.Controls
import MarathonUI.Core
import MarathonUI.Controls
import MarathonUI.Lists

MListItem {
    id: root

    property var appData: ({})

    leading: Rectangle {
        width: 48
        height: 48
        radius: 12
        color: MTheme.surfaceVariant

        MIcon {
            anchors.centerIn: parent
            source: appData.icon || "apps"
            size: 28
            color: MTheme.primary
        }
    }

    title: appData.name || "Unknown"
    subtitle: appData.description || "No description"

    trailing: Row {
        spacing: 8

        MIcon {
            source: "star"
            size: 16
            color: "#FFC107"
            anchors.verticalCenter: parent.verticalCenter
        }

        MText {
            text: (appData.rating || 0).toFixed(1)
            type: MText.Caption
            anchors.verticalCenter: parent.verticalCenter
        }

        MIcon {
            source: "chevron_right"
            size: 20
            color: MTheme.onSurfaceVariant
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
