pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Page {
    id: page

    // The runner only shares the sync service with apps that hold the storage permission.
    readonly property var dav: typeof DavSync !== "undefined" ? DavSync : null

    // The account being checked against its server, and what was typed for it.
    property string checkingId: ""
    property var entered: ({})

    function normalizedUrl(url) {
        const trimmed = url.trim();
        return /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed) ? trimmed : "https://" + trimmed;
    }

    function addAccount(displayName, baseUrl, username, secret) {
        entered = { displayName: displayName, baseUrl: baseUrl, username: username, secret: secret };
        const name = displayName.trim() !== "" ? displayName.trim() : username.trim();
        const id = dav.addAccount(name, normalizedUrl(baseUrl), username.trim(), secret, "basic");
        if (id === "")
            openAddDialog(qsTr("Couldn't add the account"));
        else
            checkingId = id;
    }

    onCheckingIdChanged: checkingId !== "" ? checkTimeout.restart() : checkTimeout.stop()

    function openAddDialog(error) {
        const dialog = pageStack.push(Qt.resolvedUrl("AddAccountDialog.qml"), Object.assign({ error: error || "" }, error ? entered : {}));
        dialog.accepted.connect(() => page.addAccount(dialog.displayName, dialog.baseUrl, dialog.username, dialog.secret));
    }

    // Discovery sends nothing for a server with no address book.
    Timer {
        id: checkTimeout

        interval: 30000
        onTriggered: {
            page.checkingId = "";
            Notices.show(qsTr("Account added, but the server didn't confirm it yet"));
        }
    }

    Connections {
        target: page.dav
        ignoreUnknownSignals: true

        function onAccountDiscovered(accountId) {
            if (accountId !== page.checkingId)
                return;
            page.checkingId = "";
            Notices.show(qsTr("Account added"));
            page.dav.syncNow();
        }
        function onAccountDiscoveryFailed(accountId, reason) {
            if (accountId !== page.checkingId)
                return;
            page.checkingId = "";
            page.dav.removeAccount(accountId);
            page.openAddDialog(qsTr("Couldn't sign in. Check the server address, username and password."));
        }
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
            SectionHeader {
                text: qsTr("CardDAV and CalDAV")
                visible: view.count > 0
            }
        }

        footer: Column {
            width: view.width
            visible: page.dav !== null && view.count > 0

            SectionHeader {
                text: qsTr("Sync")
            }
            DetailItem {
                objectName: "syncState"
                label: qsTr("Status")
                value: page.dav && page.dav.syncing ? qsTr("Syncing…") : qsTr("Idle")
            }
            DetailItem {
                objectName: "lastSync"
                label: qsTr("Last synced")
                value: page.dav && page.dav.lastSyncMs > 0 ? Format.formatDate(new Date(page.dav.lastSyncMs), Formatter.TimepointRelative) : qsTr("Never")
            }
            DetailItem {
                objectName: "lastError"
                visible: page.dav !== null && page.dav.lastError !== ""
                label: qsTr("Last error")
                value: page.dav ? page.dav.lastError : ""
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                bottomPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: qsTr("Contacts sync into the device's address book. Google needs OAuth2 and isn't supported yet; use Nextcloud, Fastmail, an iCloud app password or Mailbox.org.")
            }
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
                enabled: page.checkingId === ""
                onClicked: page.openAddDialog("")
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
                    text: item.modelData.id === page.checkingId ? qsTr("Checking account…") : item.modelData.username + " · " + item.modelData.baseUrl
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
            hintText: page.dav ? qsTr("Pull down to add a CardDAV or CalDAV account, like Nextcloud") : qsTr("Settings can't reach the sync service on this device")
        }

        VerticalScrollDecorator {}
    }
}
