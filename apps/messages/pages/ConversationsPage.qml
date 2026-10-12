pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../MessagesLogic.js" as Logic

Page {
    id: root

    property var app
    property bool archive: false
    property bool searching: false
    property string query: ""
    readonly property var visibleConversations: Logic.visibleConversations(app.conversations, app.pinnedIds, app.archivedIds, archive, query)

    Component {
        id: pageHeader
        PageHeader {
            title: root.archive ? qsTr("Archive") : qsTr("Messages")
        }
    }

    // Outside the view: a list view moves focus to its current item whenever its model changes.
    Column {
        id: searchBar
        width: parent.width
        visible: root.searching

        Loader {
            width: parent.width
            sourceComponent: pageHeader
        }
        SearchField {
            objectName: "searchField"
            width: parent.width
            placeholderText: qsTr("Search")
            onTextChanged: root.query = text.trim()
            onVisibleChanged: if (visible)
                forceActiveFocus()
            else
                text = ""
        }
    }

    SilicaListView {
        id: view
        objectName: "conversationList"
        anchors {
            top: root.searching ? searchBar.bottom : parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        clip: root.searching
        model: Logic.withSections(root.visibleConversations, root.app.pinnedIds, Date.now())
        section.property: "section"
        section.delegate: SectionHeader {
            required property string section

            visible: section !== "today"
            height: visible ? implicitHeight : 0
            text: section === "pinned" ? qsTr("Pinned") : section === "today" ? "" : Format.formatDate(new Date(Number(section)), Formatter.TimepointSectionRelative)
        }

        header: root.searching ? null : pageHeader

        PullDownMenu {
            MenuItem {
                visible: !root.archive
                text: qsTr("Archived")
                onClicked: root.app.pageStack.push(Qt.resolvedUrl("ConversationsPage.qml"), { app: root.app, archive: true })
            }
            MenuItem {
                text: root.searching ? qsTr("Hide search") : qsTr("Search")
                onClicked: root.searching = !root.searching
            }
            MenuItem {
                objectName: "newMessageItem"
                visible: !root.archive
                text: qsTr("New message")
                onClicked: root.app.newMessage()
            }
        }

        ViewPlaceholder {
            enabled: view.count === 0
            text: root.query !== "" ? qsTr("No matches") : root.archive ? qsTr("Archive is empty") : qsTr("No messages")
            hintText: root.query !== "" ? "" : root.archive ? qsTr("Archived conversations appear here") : qsTr("Pull down to write a new message")
        }

        delegate: ListItem {
            id: item

            required property var modelData
            readonly property int unread: modelData.unreadCount || 0
            readonly property bool pinned: root.app.pinnedIds.indexOf(modelData.id) !== -1
            readonly property bool archived: root.app.archivedIds.indexOf(modelData.id) !== -1
            readonly property string draft: root.app.drafts[modelData.id] || ""

            objectName: "conversation-" + modelData.id
            contentHeight: Math.max(Theme.itemSizeMedium, name.height + preview.height + 2 * Theme.paddingMedium)
            Accessible.name: Logic.displayName(modelData) + (unread > 0 ? ", " + qsTr("%n unread", "", unread) : "")
            menu: ContextMenu {
                MenuItem {
                    visible: item.unread > 0
                    text: qsTr("Mark as read")
                    onClicked: Sms.markAsRead(item.modelData.id)
                }
                MenuItem {
                    text: item.pinned ? qsTr("Unpin") : qsTr("Pin")
                    onClicked: root.app.setPinned(item.modelData.id, !item.pinned)
                }
                MenuItem {
                    text: item.archived ? qsTr("Move to inbox") : qsTr("Archive")
                    onClicked: root.app.setArchived(item.modelData.id, !item.archived)
                }
                MenuItem {
                    objectName: "deleteItem"
                    text: qsTr("Delete")
                    onClicked: {
                        const app = root.app;
                        const id = item.modelData.id;
                        item.remorseDelete(function () {
                            app.deleteConversation(id);
                        });
                    }
                }
            }
            onClicked: root.app.openConversation(modelData)

            Icon {
                id: pinIcon
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: name.verticalCenter
                visible: item.pinned
                width: visible ? Theme.iconSizeSmall : 0
                height: Theme.iconSizeSmall
                source: "image://theme/icon-s-pin"
            }
            Label {
                id: name
                anchors {
                    left: pinIcon.right
                    leftMargin: item.pinned ? Theme.paddingSmall : 0
                    right: time.left
                    rightMargin: Theme.paddingMedium
                    top: parent.top
                    topMargin: Theme.paddingMedium
                }
                text: Logic.displayName(item.modelData)
                truncationMode: TruncationMode.Fade
                color: item.highlighted || item.unread > 0 ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                id: time
                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    baseline: name.baseline
                }
                text: item.modelData.lastTimestamp ? Format.formatDate(new Date(item.modelData.lastTimestamp), isNaN(Number(item.modelData.section)) ? Formatter.TimepointRelative : Formatter.TimeValue) : ""
                font.pixelSize: Theme.fontSizeExtraSmall
                color: item.unread > 0 ? Theme.highlightColor : Theme.secondaryColor
            }
            Label {
                id: preview
                objectName: "preview"
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: count.visible ? count.left : parent.right
                    rightMargin: count.visible ? Theme.paddingMedium : Theme.horizontalPageMargin
                    top: name.bottom
                }
                text: item.draft !== "" ? qsTr("Draft: %1").arg(item.draft) : item.modelData.lastMessage
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                color: item.draft !== "" || item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
            Label {
                id: count
                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    top: name.bottom
                }
                visible: item.unread > 0
                text: item.unread
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.highlightColor
            }
        }

        VerticalScrollDecorator {}
    }
}
