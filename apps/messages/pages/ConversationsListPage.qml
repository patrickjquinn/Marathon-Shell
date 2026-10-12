pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Modals
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Marathon DS · Messages list (screens-apps-1.jsx:234).
//
// MTopBar with "Messages", search field, 44×44 monogram rows beneath,
// name + time + snippet + teal-bright unread count badge, compose FAB.
// Three-tab bottom nav: Pinned · All · Archive.
Page {
    id: conversationsPage

    required property var app

    property string selectedTab: "all"        // "pinned" | "all" | "archive"
    property string searchQuery: ""
    // Deleted only when the Undo snackbar expires.
    property string pendingDeleteId: ""
    readonly property bool sheetOpen: contextMenu.showing

    readonly property var filteredConversations: {
        const pinned = conversationsPage.app.pinnedIds;
        const archived = conversationsPage.app.archivedIds;
        const query = searchQuery.toLowerCase();
        var list = conversationsPage.app.conversations.filter(c => {
            if (c.id === pendingDeleteId)
                return false;
            var isArchived = archived.indexOf(c.id) !== -1;
            if (selectedTab === "archive" ? !isArchived : isArchived)
                return false;
            if (selectedTab === "pinned" && pinned.indexOf(c.id) === -1)
                return false;
            if (query.length === 0)
                return true;
            return (c.contactName && c.contactName.toLowerCase().includes(query)) || (c.contactNumber && MPhoneNumber.digits(query).length > 0 && MPhoneNumber.digits(c.contactNumber).includes(MPhoneNumber.digits(query))) || (c.lastMessage && c.lastMessage.toLowerCase().includes(query));
        });
        if (selectedTab === "all")
            list.sort((a, b) => (pinned.indexOf(b.id) !== -1) - (pinned.indexOf(a.id) !== -1));
        return list;
    }

    signal openConversation(string conversationId)
    signal newMessage

    function commitPendingDelete() {
        if (pendingDeleteId === "")
            return;
        const id = pendingDeleteId;
        pendingDeleteId = "";
        conversationsPage.app.setPinned(id, false);
        conversationsPage.app.setArchived(id, false);
        conversationsPage.app.setDraft(id, "");
        SMSService.deleteConversation(id);
    }

    function deleteConversation(conversationId) {
        commitPendingDelete();
        pendingDeleteId = conversationId;
        snackbar.show("Conversation deleted", "Undo");
    }

    function closeSheet() {
        contextMenu.hide();
    }

    function monogramOf(name) {
        if (!name)
            return "·";
        const parts = name.split(/\s+/).filter(p => p.length > 0);
        if (parts.length === 0)
            return "·";
        if (parts.length === 1)
            return parts[0].substring(0, 2).toUpperCase();
        return String(parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    Component.onDestruction: commitPendingDelete()

    background: Rectangle {
        color: MColors.background
    }

    Column {
        anchors.fill: parent
        spacing: 0

        MTopBar {
            id: topBar
            width: parent.width
            title: "Messages"
        }

        Item {
            width: parent.width
            height: searchField.height + MSpacing.sm * 2

            MSearchField {
                id: searchField
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                placeholder: "Search messages"
                onTextChanged: conversationsPage.searchQuery = text.trim()
            }
        }

        ListView {
            id: conversationsList
            width: parent.width
            height: parent.height - topBar.height - searchField.parent.height - tabBar.height
            clip: true
            model: conversationsPage.filteredConversations
            spacing: 0
            bottomMargin: composeFab.height + MSpacing.lg * 2

            MEmptyState {
                visible: conversationsList.count === 0
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "message-circle"
                title: conversationsPage.searchQuery !== "" ? "No matches" : conversationsPage.selectedTab === "pinned" ? "No pinned conversations" : conversationsPage.selectedTab === "archive" ? "Archive is empty" : "No conversations yet"
                message: conversationsPage.searchQuery !== "" ? "No conversations match \"" + conversationsPage.searchQuery + "\"." : conversationsPage.selectedTab === "pinned" ? "Press and hold a conversation, then choose Pin." : conversationsPage.selectedTab === "archive" ? "Press and hold a conversation, then choose Archive." : "Tap New message to start a conversation."
            }

            delegate: Item {
                id: row

                required property var modelData
                readonly property string displayName: modelData.contactName || MPhoneNumber.format(modelData.contactNumber) || "Unknown"
                readonly property bool pinned: conversationsPage.app.pinnedIds.indexOf(modelData.id) !== -1
                readonly property string draft: conversationsPage.app.drafts[modelData.id] || ""

                function openMenu() {
                    HapticService.medium();
                    contextMenu.conversationId = modelData.id;
                    contextMenu.isUnread = (modelData.unreadCount || 0) > 0;
                    contextMenu.show();
                }

                width: conversationsList.width
                height: 70

                Accessible.role: Accessible.Button
                Accessible.name: displayName + ((modelData.unreadCount || 0) > 0 ? ", " + modelData.unreadCount + " unread" : "")
                Accessible.onPressAction: conversationsPage.openConversation(modelData.id || modelData.contactNumber || "")

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    spacing: 12

                    // 44 × 44 monogram avatar circle.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 44
                        radius: width / 2
                        color: conversationsPage.app.tintFor(row.modelData.contactName || row.modelData.contactNumber || "?")
                        border.width: 1
                        border.color: MColors.whiteOverlay08

                        Text {
                            anchors.centerIn: parent
                            text: conversationsPage.monogramOf(row.modelData.contactName || row.modelData.contactNumber || "·")
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeSubhead
                            font.weight: Font.DemiBold
                        }
                    }

                    Column {
                        width: parent.width - 44 - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        // Name + time row.
                        Item {
                            width: parent.width
                            height: nameText.implicitHeight

                            Icon {
                                id: pinIcon
                                anchors.left: parent.left
                                anchors.verticalCenter: nameText.verticalCenter
                                visible: row.pinned
                                width: visible ? implicitWidth : 0
                                name: "push-pin"
                                size: 14
                                color: MColors.textSecondary
                            }
                            Text {
                                id: nameText
                                anchors.left: pinIcon.right
                                anchors.leftMargin: row.pinned ? MSpacing.xs : 0
                                anchors.right: timeText.left
                                anchors.rightMargin: 8
                                text: row.displayName
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                id: timeText
                                anchors.right: parent.right
                                anchors.verticalCenter: nameText.verticalCenter
                                text: row.modelData.lastTimestamp ? conversationsPage.app.formatTimestamp(row.modelData.lastTimestamp) : ""
                                color: (row.modelData.unreadCount || 0) > 0 ? MColors.marathonTealBright : MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeEyebrow
                                font.weight: Font.Medium
                                font.features: ({
                                        "tnum": 1
                                    })
                            }
                        }

                        // Snippet + unread badge.
                        Item {
                            width: parent.width
                            height: snippetText.implicitHeight

                            Text {
                                id: snippetText
                                anchors.left: parent.left
                                anchors.right: badge.visible ? badge.left : parent.right
                                anchors.rightMargin: badge.visible ? 8 : 0
                                text: row.draft !== "" ? "Draft: " + row.draft : (row.modelData.lastMessage || "")
                                color: row.draft !== "" ? MColors.marathonTealBright : MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.weight: Font.Normal
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }

                            Rectangle {
                                id: badge
                                anchors.right: parent.right
                                anchors.verticalCenter: snippetText.verticalCenter
                                height: 18
                                radius: MRadius.md
                                color: MColors.marathonTealBright
                                visible: (row.modelData.unreadCount || 0) > 0
                                width: badgeText.implicitWidth + 14

                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: String(row.modelData.unreadCount || 0)
                                    color: MColors.textOnAccent
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeEyebrow
                                    font.weight: Font.Bold
                                    font.features: ({
                                            "tnum": 1
                                        })
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: 12 + 44 + 12
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    height: 1
                    color: MColors.whiteOverlay04
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        conversationsPage.openConversation(row.modelData.id || row.modelData.contactNumber || "");
                    }
                    onPressAndHold: row.openMenu()
                }
            }
        }

        // ── Bottom tab bar — Pinned · All · Archive ──────────────
        MTabBar {
            id: tabBar
            width: parent.width
            activeTab: conversationsPage.selectedTab === "pinned" ? 0 : conversationsPage.selectedTab === "all" ? 1 : 2
            tabs: [
                {
                    "label": "Pinned",
                    "icon": "push-pin"
                },
                {
                    "label": "All",
                    "icon": "message-circle"
                },
                {
                    "label": "Archive",
                    "icon": "archive"
                }
            ]
            onTabSelected: index => {
                HapticService.light();
                conversationsPage.selectedTab = ["pinned", "all", "archive"][index];
            }
        }
    }

    MFloatingActionButton {
        id: composeFab
        label: "New message"
        iconName: "pencil-simple"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: MSpacing.lg
        anchors.bottomMargin: tabBar.height + MSpacing.lg + (snackbar.open ? snackbar.height + MSpacing.md : 0)
        onClicked: conversationsPage.newMessage()
    }

    MSnackbar {
        id: snackbar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        anchors.bottomMargin: tabBar.height + MSpacing.md
        onActionTriggered: conversationsPage.pendingDeleteId = ""
        onExpired: conversationsPage.commitPendingDelete()
    }

    MSheet {
        id: contextMenu

        property string conversationId: ""
        property bool isUnread: false
        readonly property bool isPinned: conversationsPage.app.pinnedIds.indexOf(conversationId) !== -1
        readonly property bool isArchived: conversationsPage.app.archivedIds.indexOf(conversationId) !== -1

        title: "Conversation Options"

        content: Column {
            width: parent.width
            spacing: 0

            MSettingsListItem {
                visible: contextMenu.isUnread
                title: "Mark as Read"
                iconName: "check"
                showChevron: false
                onSettingClicked: {
                    SMSService.markAsRead(contextMenu.conversationId);
                    HapticService.light();
                    contextMenu.hide();
                }
            }

            MSettingsListItem {
                title: contextMenu.isPinned ? "Unpin" : "Pin"
                iconName: "push-pin"
                showChevron: false
                onSettingClicked: {
                    conversationsPage.app.setPinned(contextMenu.conversationId, !contextMenu.isPinned);
                    HapticService.light();
                    contextMenu.hide();
                }
            }

            MSettingsListItem {
                title: contextMenu.isArchived ? "Move to Inbox" : "Archive"
                iconName: "archive"
                showChevron: false
                onSettingClicked: {
                    conversationsPage.app.setArchived(contextMenu.conversationId, !contextMenu.isArchived);
                    HapticService.light();
                    contextMenu.hide();
                }
            }

            MSettingsListItem {
                title: "Delete Conversation"
                iconName: "trash"
                showChevron: false
                onSettingClicked: {
                    conversationsPage.deleteConversation(contextMenu.conversationId);
                    HapticService.medium();
                    contextMenu.hide();
                }
            }
        }
    }
}
