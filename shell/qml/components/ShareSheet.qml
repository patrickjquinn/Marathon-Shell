import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: shareSheet

    property var content: null
    property string contentType: "text"

    anchors.fill: parent
    visible: UIStore.shareSheetOpen
    z: 2600

    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: "#000000"
        opacity: shareSheet.visible ? 0.7 : 0

        MouseArea {
            anchors.fill: parent
            onClicked: UIStore.closeShareSheet()
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    Rectangle {
        id: sheet

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.round(400 * Constants.scaleFactor)
        radius: Constants.borderRadiusMedium
        color: Qt.rgba(15, 15, 15, 0.98)
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.15)
        layer.enabled: true
        y: shareSheet.visible ? 0 : parent.height

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.05)
        }

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: Constants.spacingMedium

            Row {
                width: parent.width
                height: Constants.touchTargetMinimum

                Text {
                    text: "Share"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.DemiBold
                    font.family: MTypography.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width: parent.width - Math.round(100 * Constants.scaleFactor)
                    height: Constants.dividerHeight
                }

                Rectangle {
                    width: Constants.touchTargetMinimum
                    height: Constants.touchTargetMinimum
                    radius: Constants.borderRadiusSmall
                    color: Qt.rgba(255, 255, 255, 0.08)

                    Icon {
                        name: "x"
                        size: Constants.iconSizeSmall
                        color: MColors.textPrimary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: UIStore.closeShareSheet()
                    }
                }
            }

            GridView {
                width: parent.width
                height: parent.height - 56
                cellWidth: width / 4
                cellHeight: 100
                clip: true
                model: [
                    {
                        "name": "Messages",
                        "icon": "message-square",
                        "appId": "messages"
                    },
                    {
                        "name": "Email",
                        "icon": "mail",
                        "appId": "email"
                    },
                    {
                        "name": "Notes",
                        "icon": "file-text",
                        "appId": "notes"
                    },
                    {
                        "name": "Copy Link",
                        "icon": "link",
                        "appId": "clipboard"
                    }
                ]

                delegate: Item {
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight

                    Column {
                        anchors.centerIn: parent
                        spacing: Constants.spacingSmall

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.round(56 * Constants.scaleFactor)
                            height: Math.round(56 * Constants.scaleFactor)
                            radius: Constants.borderRadiusSmall
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.width: 1
                            border.color: targetMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.6) : Qt.rgba(255, 255, 255, 0.08)

                            Icon {
                                name: modelData.icon
                                size: Constants.iconSizeMedium
                                color: MColors.textPrimary
                                anchors.centerIn: parent
                            }

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        Text {
                            text: modelData.name
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeSmall
                            font.family: MTypography.fontFamily
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        id: targetMouseArea

                        anchors.fill: parent
                        onClicked: {
                            Logger.info("ShareSheet", "Share to: " + modelData.name);
                            HapticService.light();
                            UIStore.closeShareSheet();
                        }
                    }
                }
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
    }

    Connections {
        function onShowShareSheet(content, type) {
            shareSheet.content = content;
            shareSheet.contentType = type;
        }

        target: UIStore
    }
}
