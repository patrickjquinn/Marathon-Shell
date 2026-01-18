import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: root

    property var appData: ({})

    signal clicked

    radius: 16
    color: MColors.elevated

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: MColors.accent
            opacity: parent.pressed ? 0.1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 12

        Row {
            width: parent.width
            spacing: 15

            Rectangle {
                width: 56
                height: 56
                radius: 14
                color: MColors.surface

                Icon {
                    anchors.centerIn: parent
                    name: appData.icon || "apps"
                    size: 36
                    color: MColors.accent
                }
            }

            Column {
                width: parent.width - 71
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter

                MLabel {
                    text: appData.name || "Unknown"
                    variant: "large"
                    color: MColors.textPrimary
                    elide: Text.ElideRight
                }

                Row {
                    spacing: 5

                    Icon {
                        name: "star"
                        size: 14
                        color: "#FFC107"
                    }

                    MLabel {
                        text: (appData.rating || 0).toFixed(1)
                        variant: "xsmall"
                        color: MColors.textSecondary
                    }
                }
            }
        }

        MLabel {
            width: parent.width
            text: appData.description || ""
            variant: "small"
            color: MColors.textSecondary
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
}
