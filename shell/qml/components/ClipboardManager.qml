pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Rectangle {
    id: clipboardManager

    anchors.fill: parent
    color: Silica.Theme.rgba("black", 0.85)
    visible: UIStore.clipboardManagerOpen
    z: 2650
    opacity: visible ? 1 : 0

    MouseArea {
        anchors.fill: parent
        onClicked: UIStore.closeClipboardManager()
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight
        anchors.bottomMargin: Constants.navBarHeight

        Item {
            id: header

            width: parent.width
            height: Silica.Theme.itemSizeLarge

            Silica.BackgroundItem {
                anchors.left: parent.left
                width: clearLabel.width + Silica.Theme.horizontalPageMargin * 2
                height: parent.height
                onClicked: {
                    ClipboardManagerCpp.clearHistory();
                    HapticManager.light();
                }

                Silica.Label {
                    id: clearLabel

                    anchors.left: parent.left
                    anchors.leftMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Clear"
                    color: parent.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                }
            }

            Silica.Label {
                anchors.right: parent.right
                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: "Clipboard History"
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
                font.family: Silica.Theme.fontFamilyHeading
            }
        }

        ListView {
            id: clipList

            width: parent.width
            height: parent.height - header.height
            clip: true
            model: ClipboardManagerCpp.history

            delegate: Silica.BackgroundItem {
                id: clipItem

                required property int index
                required property var modelData

                width: ListView.view.width
                height: Math.max(Silica.Theme.itemSizeMedium, clipText.height + Silica.Theme.paddingMedium * 2)
                onClicked: {
                    Logger.info("ClipboardManager", "Selected item: " + clipItem.modelData.text.substring(0, 30));
                    ClipboardManagerCpp.copyToClipboard(clipItem.modelData.text);
                    HapticManager.light();
                    UIStore.closeClipboardManager();
                }

                Column {
                    id: clipText

                    anchors.left: parent.left
                    anchors.leftMargin: Silica.Theme.horizontalPageMargin
                    anchors.right: deleteButton.left
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        text: clipItem.modelData.text
                        color: clipItem.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Silica.Label {
                        text: {
                            var date = new Date(clipItem.modelData.timestamp);
                            return Qt.formatDateTime(date, "hh:mm AP");
                        }
                        color: clipItem.highlighted ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    }
                }

                Silica.IconButton {
                    id: deleteButton

                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.paddingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-delete"
                    Accessible.name: "Delete"
                    onClicked: {
                        ClipboardManagerCpp.deleteItem(clipItem.index);
                        HapticManager.light();
                    }
                }
            }
        }
    }

    Silica.Label {
        visible: clipList.count === 0
        anchors.centerIn: parent
        text: "No clipboard history"
        color: Silica.Theme.secondaryHighlightColor
        font.pixelSize: Silica.Theme.fontSizeExtraLarge
        font.family: Silica.Theme.fontFamilyHeading
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
}
