pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../core/Clock.js" as Clock

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

    Item {
        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight
        anchors.bottomMargin: Constants.navBarHeight

        Silica.SilicaListView {
            id: clipList

            anchors.fill: parent
            clip: true
            model: ClipboardManagerCpp.history

            header: Silica.PageHeader {
                title: qsTr("Clipboard history")
            }

            Silica.PullDownMenu {
                visible: clipList.count > 0

                Silica.MenuItem {
                    objectName: "clearHistory"
                    text: qsTr("Clear history")
                    onClicked: clearRemorse.execute(qsTr("Clearing history"), () => ClipboardManagerCpp.clearHistory())
                }
            }

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
                        text: Clock.format(new Date(clipItem.modelData.timestamp), SettingsManagerCpp.timeFormat)
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
                    //: Accessible name of the button that deletes a clipboard entry
                    Accessible.name: qsTr("Delete")
                    onClicked: {
                        ClipboardManagerCpp.deleteItem(clipItem.index);
                        HapticManager.light();
                    }
                }
            }
        }

        Silica.RemorsePopup {
            id: clearRemorse

            objectName: "clearRemorse"
        }
    }

    Silica.Label {
        visible: clipList.count === 0
        anchors.centerIn: parent
        text: qsTr("No clipboard history")
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
