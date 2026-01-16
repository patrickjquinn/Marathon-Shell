import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

MListTile {
    id: root

    property var appData: ({})

    title: appData.name || "Unknown"
    subtitle: appData.description || "No description"

    leading: Rectangle {
        width: 48
        height: 48
        radius: 12
        color: MColors.elevated

        Icon {
            anchors.centerIn: parent
            name: appData.icon || "apps"
            size: 28
            color: MColors.accent
        }
    }

    trailing: Row {
        spacing: 8

        Icon {
            name: "star"
            size: 16
            color: "#FFC107"
            anchors.verticalCenter: parent.verticalCenter
        }

        MLabel {
            text: (appData.rating || 0).toFixed(1)
            variant: "xsmall"
            color: MColors.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }

        Icon {
            name: "chevron-right"
            size: 20
            color: MColors.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
