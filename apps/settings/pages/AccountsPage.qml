pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    // The runner only shares the sync service with apps that hold the storage permission.
    readonly property var dav: typeof DavSync !== "undefined" ? DavSync : null

    function addAccount(displayName, baseUrl, username, secret) {
        dav.addAccount(displayName !== "" ? displayName : username, baseUrl, username, secret, "basic");
    }

    function openAddDialog() {
        const dialog = pageStack.push(Qt.resolvedUrl("AddAccountDialog.qml"));
        dialog.accepted.connect(() => page.addAccount(dialog.displayName, dialog.baseUrl, dialog.username, dialog.secret));
    }

    SilicaListView {
        id: view

        objectName: "accountList"
        anchors.fill: parent
        model: page.dav ? page.dav.accounts : []

        header: Column {
            width: view.width

            PageHeader {
                title: qsTr("Accounts")
            }
            DetailItem {
                objectName: "syncState"
                visible: page.dav !== null
                label: qsTr("Sync")
                value: page.dav && page.dav.syncing ? qsTr("Syncing…") : qsTr("Idle")
            }
            DetailItem {
                objectName: "lastSync"
                visible: page.dav !== null
                label: qsTr("Last synced")
                value: page.dav && page.dav.lastSyncMs > 0 ? Format.formatDate(new Date(page.dav.lastSyncMs), Formatter.TimepointRelative) : qsTr("Never")
            }
            DetailItem {
                objectName: "lastError"
                visible: page.dav !== null && page.dav.lastError !== ""
                label: qsTr("Last error")
                value: page.dav ? page.dav.lastError : ""
            }
            SectionHeader {
                text: qsTr("CardDAV and CalDAV")
                visible: view.count > 0
            }
        }

        footer: Label {
            x: Theme.horizontalPageMargin
            width: view.width - 2 * Theme.horizontalPageMargin
            topPadding: Theme.paddingLarge
            bottomPadding: Theme.paddingLarge
            visible: page.dav !== null
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("Contacts sync into the device's address book. Google needs OAuth2 and isn't supported yet; use Nextcloud, Fastmail, an iCloud app password or Mailbox.org.")
        }

        PullDownMenu {
            visible: page.dav !== null

            MenuItem {
                objectName: "syncItem"
                text: qsTr("Sync now")
                enabled: page.dav !== null && !page.dav.syncing && page.dav.accountCount > 0
                onClicked: page.dav.syncNow()
            }
            MenuItem {
                objectName: "addItem"
                text: qsTr("Add account")
                onClicked: page.openAddDialog()
            }
        }

        delegate: ListItem {
            id: item

            required property var modelData

            objectName: "account-" + modelData.id
            contentHeight: Theme.itemSizeMedium
            Accessible.name: modelData.displayName + ", " + modelData.username
            menu: ContextMenu {
                MenuItem {
                    objectName: "removeItem"
                    text: qsTr("Remove")
                    onClicked: item.remorseDelete(() => page.dav.removeAccount(item.modelData.id))
                }
            }
            onClicked: openMenu()

            Column {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.modelData.displayName
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.modelData.username + " · " + item.modelData.baseUrl
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: view.count === 0
            text: page.dav ? qsTr("No accounts") : qsTr("Accounts aren't available")
            hintText: page.dav ? qsTr("Pull down to add a CardDAV or CalDAV account") : qsTr("Settings can't reach the sync service on this device")
        }

        VerticalScrollDecorator {}
    }
}
