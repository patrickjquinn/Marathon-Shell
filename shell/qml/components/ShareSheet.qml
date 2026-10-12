pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

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
        height: sheetColumn.height + Constants.navBarHeight
        color: Silica.Theme.rgba("black", 0.85)
        y: shareSheet.visible ? 0 : parent.height

        Column {
            id: sheetColumn

            width: parent.width

            Item {
                width: parent.width
                height: Silica.Theme.itemSizeLarge

                Silica.IconButton {
                    anchors.left: parent.left
                    anchors.leftMargin: Silica.Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-close"
                    Accessible.name: "Close"
                    onClicked: UIStore.closeShareSheet()
                }

                Silica.Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Share"
                    color: Silica.Theme.highlightColor
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    font.family: Silica.Theme.fontFamilyHeading
                }
            }

            Repeater {
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

                delegate: Silica.BackgroundItem {
                    id: shareTarget

                    required property var modelData

                    width: sheetColumn.width
                    height: Silica.Theme.itemSizeMedium
                    onClicked: {
                        Logger.info("ShareSheet", "Share to: " + shareTarget.modelData.name);
                        HapticManager.light();
                        UIStore.closeShareSheet();
                    }

                    GlyphIcon {
                        id: targetIcon

                        x: Silica.Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        name: shareTarget.modelData.icon
                        size: Silica.Theme.iconSizeMedium
                        color: shareTarget.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    }

                    Silica.Label {
                        anchors.left: targetIcon.right
                        anchors.leftMargin: Silica.Theme.paddingLarge
                        anchors.right: parent.right
                        anchors.rightMargin: Silica.Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: shareTarget.modelData.name
                        color: shareTarget.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                        truncationMode: Silica.TruncationMode.Fade
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
}
