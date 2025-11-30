import QtQuick
import QtQuick.Controls
import MarathonUI.Core
import MarathonUI.Controls

Rectangle {
    id: root

    property var appData: ({})
    signal clicked

    radius: 16
    color: MTheme.surfaceVariant

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()

        Rectangle {
            anchors.fill: parent
            radius: parent.parent.radius
            color: MTheme.primary
            opacity: parent.pressed ? 0.1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }
    }

    MColumn {
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
                color: MTheme.surface

                MIcon {
                    anchors.centerIn: parent
                    source: appData.icon || "apps"
                    size: 36
                    color: MTheme.primary
                }
            }

            MColumn {
                width: parent.width - 71
                spacing: 4
                anchors.verticalCenter: parent.verticalCenter

                MText {
                    text: appData.name || "Unknown"
                    type: MText.Subtitle
                    elide: Text.ElideRight
                }

                Row {
                    spacing: 5

                    MIcon {
                        source: "star"
                        size: 14
                        color: "#FFC107"
                    }

                    MText {
                        text: (appData.rating || 0).toFixed(1)
                        type: MText.Caption
                        color: MTheme.onSurfaceVariant
                    }
                }
            }
        }

        MText {
            width: parent.width
            text: appData.description || ""
            type: MText.Body
            color: MTheme.onSurfaceVariant
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }
}
