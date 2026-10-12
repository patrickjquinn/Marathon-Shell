pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app
    readonly property var mail: app.mail

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "addAccountItem"
                text: qsTr("Add account")
                onClicked: pageStack.push(Qt.resolvedUrl("AddAccountPage.qml"), { app: page.app })
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
                model: page.mail.accounts

                Column {
                    id: account

                    required property string display
                    // MailService only exposes the current account's folder.
                    readonly property bool current: display === page.mail.currentAccountName

                    width: column.width

                    SectionHeader {
                        text: account.display
                    }
                    ListItem {
                        objectName: "folder-" + account.display
                        enabled: account.current
                        opacity: enabled ? 1 : Theme.opacityLow
                        contentHeight: Theme.itemSizeSmall
                        Accessible.name: folderLabel.text + (countLabel.visible ? ", " + qsTr("%n unread", "", page.mail.unreadCount) : "")
                        onClicked: page.app.showInbox()

                        Icon {
                            id: folderIcon

                            x: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/icon-m-mail"
                            color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            id: folderLabel

                            anchors {
                                left: folderIcon.right
                                leftMargin: Theme.paddingMedium
                                right: countLabel.left
                                rightMargin: Theme.paddingMedium
                                verticalCenter: parent.verticalCenter
                            }
                            text: account.current && page.mail.currentFolderName !== "" ? page.mail.currentFolderName : qsTr("Inbox")
                            truncationMode: TruncationMode.Fade
                            color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            id: countLabel

                            anchors {
                                right: parent.right
                                rightMargin: Theme.horizontalPageMargin
                                verticalCenter: parent.verticalCenter
                            }
                            visible: account.current && page.mail.unreadCount > 0
                            text: page.mail.unreadCount
                            color: Theme.highlightColor
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
