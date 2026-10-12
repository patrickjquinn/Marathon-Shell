pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MailLogic.js" as Logic

Page {
    id: page

    property var app
    readonly property var mail: app.mail
    readonly property string syncState: app.serviceAvailable ? mail.syncState : ""
    readonly property int count: app.hasAccount ? view.count : 0
    readonly property bool syncing: app.hasAccount && syncState === "syncing"
    readonly property bool waiting: app.hasAccount && count === 0 && syncState !== "idle" && syncState !== "error"
    // Past this the server isn't answering; stop spinning and say so.
    property bool timedOut: false
    readonly property bool loading: waiting && !timedOut
    readonly property bool syncFailed: app.hasAccount && (syncState === "error" || (waiting && timedOut))

    function remorseMove(kind) {
        remorse.execute(kind === "archive" ? qsTr("Archived") : qsTr("Deleted"), function () {
            page.app.commitPendingMove();
        });
    }

    objectName: "inboxPage"
    onSyncStateChanged: timedOut = false

    Timer {
        objectName: "syncTimeout"
        interval: 15000
        running: page.loading
        onTriggered: page.timedOut = true
    }

    RemorsePopup {
        id: remorse

        objectName: "remorse"
        onCanceled: page.app.cancelPendingMove()
    }

    SilicaListView {
        id: view

        objectName: "messageView"
        anchors.fill: parent
        model: page.app.hasAccount ? page.mail.messages : null

        header: Column {
            width: view.width

            PageHeader {
                title: page.app.hasAccount ? page.mail.currentFolderName || qsTr("Inbox") : qsTr("Mail")
                description: page.app.hasAccount ? Logic.headerDescription(page.mail.currentAccountName, page.mail.unreadCount, page.mail.outboxCount) : ""
            }
            Label {
                objectName: "syncError"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.syncFailed && page.count > 0
                text: qsTr("Couldn't check for new mail. Check your connection, then pull down to sync.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.errorColor
                bottomPadding: Theme.paddingMedium
            }
        }

        PullDownMenu {
            objectName: "pulley"
            visible: page.app.serviceAvailable
            busy: page.syncing

            MenuItem {
                objectName: "accountsItem"
                text: page.app.hasAccount ? qsTr("Accounts") : qsTr("Add account")
                onClicked: pageStack.push(Qt.resolvedUrl(page.app.hasAccount ? "AccountsPage.qml" : "AddAccountPage.qml"), { app: page.app })
            }
            MenuItem {
                objectName: "syncItem"
                visible: page.app.hasAccount
                text: page.syncing ? qsTr("Stop") : qsTr("Sync")
                onClicked: {
                    page.timedOut = false;
                    if (page.syncing)
                        page.mail.cancelSync();
                    else
                        page.mail.refresh();
                }
            }
            MenuItem {
                objectName: "draftItem"
                visible: page.app.hasAccount && page.app.drafts.length > 0
                text: page.app.drafts.length === 1 ? qsTr("Continue draft") : qsTr("Drafts")
                onClicked: page.app.continueDraft()
            }
            MenuItem {
                objectName: "newMessageItem"
                visible: page.app.hasAccount
                text: qsTr("New message")
                onClicked: page.app.compose()
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: !page.loading && page.count === 0
            text: !page.app.serviceAvailable ? qsTr("Mail isn't available") : !page.app.hasAccount ? qsTr("No mail accounts") : page.syncFailed ? qsTr("Couldn't load your mail") : page.app.folderKind === "inbox" ? qsTr("Inbox zero") : page.app.folderKind === "outbox" ? qsTr("Nothing waiting to send") : qsTr("No messages")
            hintText: !page.app.serviceAvailable ? qsTr("Close Mail and open it again. If that doesn't help, restart your phone.") : !page.app.hasAccount ? qsTr("Pull down to add one") : page.syncFailed ? qsTr("Check your connection, then pull down to sync") : page.app.folderKind === "inbox" ? qsTr("All caught up") : ""
        }

        BusyLabel {
            objectName: "busy"
            running: page.loading
            text: qsTr("Checking for mail")
        }

        delegate: ListItem {
            id: item

            required property var model
            readonly property string messageId: String(model.messageId)
            readonly property bool unread: model.unread === true
            readonly property bool attachment: model.hasAttachment == true

            hidden: messageId === page.app.pendingMoveId
            contentHeight: Theme.itemSizeExtraLarge
            Accessible.name: (unread ? qsTr("Unread") + ", " : "") + (model.from || "") + ", " + (model.subject || "")
            onClicked: page.app.openMessage(messageId)
            menu: ContextMenu {
                MenuItem {
                    objectName: "readItem"
                    text: item.unread ? qsTr("Mark as read") : qsTr("Mark as unread")
                    onClicked: page.mail.markAsRead(item.messageId, item.unread)
                }
                MenuItem {
                    objectName: "archiveItem"
                    text: qsTr("Archive")
                    onClicked: item.remorseAction(qsTr("Archived"), function () {
                        page.app.move(item.messageId, "archive");
                    })
                }
                MenuItem {
                    objectName: "deleteItem"
                    text: qsTr("Delete")
                    onClicked: item.remorseDelete(function () {
                        page.app.move(item.messageId, "trash");
                    })
                }
            }

            Rectangle {
                objectName: "unreadMarker"
                visible: item.unread
                width: Theme.paddingSmall
                height: parent.height - 2 * Theme.paddingLarge
                anchors.verticalCenter: parent.verticalCenter
                radius: width / 2
                color: Theme.highlightColor
            }
            Column {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter

                Item {
                    width: parent.width
                    height: sender.height

                    Label {
                        id: sender

                        anchors {
                            left: parent.left
                            right: attachIcon.visible ? attachIcon.left : time.left
                            rightMargin: Theme.paddingMedium
                        }
                        text: item.model.from || ""
                        truncationMode: TruncationMode.Fade
                        color: item.unread || item.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Icon {
                        id: attachIcon

                        anchors {
                            right: time.left
                            rightMargin: Theme.paddingSmall
                            verticalCenter: sender.verticalCenter
                        }
                        visible: item.attachment
                        source: "image://theme/icon-s-attach"
                        color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                    Label {
                        id: time

                        anchors {
                            right: parent.right
                            baseline: sender.baseline
                        }
                        text: item.model.timestamp || ""
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                }
                Label {
                    width: parent.width
                    text: item.model.subject || qsTr("(No subject)")
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: String(item.model.snippet || "").replace(/\s+/g, " ").trim()
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
