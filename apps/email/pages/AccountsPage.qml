pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MailLogic.js" as Logic

Page {
    id: page

    property var app
    readonly property var mail: app.mail

    objectName: "accountsPage"
    onStatusChanged: if (status === PageStatus.Activating)
        mail.accountList.forEach(a => mail.refreshFolders(a.id))

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "addAccountItem"
                text: qsTr("Add account")
                onClicked: pageStack.push(Qt.resolvedUrl("AddAccountPage.qml"), {
                    app: page.app
                })
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Accounts")
            }

            Repeater {
                objectName: "accounts"
                model: page.mail.accountList

                Column {
                    id: account

                    required property var modelData

                    width: column.width

                    SectionHeader {
                        text: account.modelData.name
                    }
                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        visible: account.modelData.folders.length === 0
                        bottomPadding: Theme.paddingMedium
                        text: qsTr("Folders appear after the first sync")
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                    }
                    Repeater {
                        model: account.modelData.folders

                        ListItem {
                            id: folder

                            required property var modelData
                            readonly property bool current: account.modelData.id === page.mail.currentAccountId && modelData.id === page.mail.currentFolderId
                            // Outbox and Drafts count what's in them; other folders count unread.
                            readonly property int shown: modelData.kind === "outbox" || modelData.kind === "drafts" ? modelData.count : modelData.unread

                            objectName: "folder-" + account.modelData.name + "-" + modelData.kind
                            contentHeight: Theme.itemSizeSmall
                            Accessible.name: modelData.name + (shown > 0 ? ", " + shown : "")
                            onClicked: page.app.openFolder(account.modelData.id, modelData.id, modelData.kind)

                            Icon {
                                id: folderIcon

                                x: Theme.horizontalPageMargin
                                anchors.verticalCenter: parent.verticalCenter
                                source: Logic.folderIcon(folder.modelData.kind)
                                color: folder.highlighted || folder.current ? Theme.highlightColor : Theme.primaryColor
                            }
                            Label {
                                anchors {
                                    left: folderIcon.right
                                    leftMargin: Theme.paddingMedium
                                    right: countLabel.left
                                    rightMargin: Theme.paddingMedium
                                    verticalCenter: parent.verticalCenter
                                }
                                objectName: "folderName"
                                text: folder.modelData.name
                                truncationMode: TruncationMode.Fade
                                color: folder.highlighted || folder.current ? Theme.highlightColor : Theme.primaryColor
                            }
                            Label {
                                id: countLabel

                                anchors {
                                    right: parent.right
                                    rightMargin: Theme.horizontalPageMargin
                                    verticalCenter: parent.verticalCenter
                                }
                                visible: folder.shown > 0
                                text: folder.shown
                                color: Theme.highlightColor
                            }
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
