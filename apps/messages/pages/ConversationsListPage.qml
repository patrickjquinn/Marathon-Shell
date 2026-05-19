import MarathonApp.Messages
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
// MTopBar with "Messages" + search + small 32×32 teal-gradient compose
// squircle. 44×44 monogram rows beneath, name + time + snippet +
// teal-bright unread count badge. Three-tab bottom nav:
// Pinned · All · Archive.
Page {
    id: conversationsPage

    property var filteredConversations: messagesApp.conversations
    property string selectedTab: "all"        // "pinned" | "all" | "archive"
    property string searchQuery: ""

    signal openConversation(string conversationId)
    signal newMessage

    function updateFilter() {
        var conversations = messagesApp.conversations;
        if (selectedTab === "pinned")
            conversations = conversations.filter(function (c) {
                return c.pinned === true;
            });
        else if (selectedTab === "archive")
            conversations = conversations.filter(function (c) {
                return c.archived === true;
            });
        if (searchQuery.length > 0) {
            var query = searchQuery.toLowerCase();
            conversations = conversations.filter(function (c) {
                return (c.contactName && c.contactName.toLowerCase().includes(query)) || (c.contactNumber && c.contactNumber.includes(query)) || (c.lastMessage && c.lastMessage.toLowerCase().includes(query));
            });
        }
        filteredConversations = conversations;
    }

    function deleteConversation(conversationId) {
        SMSService.deleteConversation(conversationId);
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

    // Tint palette: pseudo-random per contact, drawn from the DS
    // secondary-accent ramp + a few brand-aware tones.
    function tintFor(name) {
        const palette = ["#3a6b9c", "#a85968", "#6b5d8f", "#1a4a3e", "#4a8a5e", "#c89545", MColors.elev3];
        let h = 0;
        for (let i = 0; i < name.length; ++i) {
            h = (h * 31 + name.charCodeAt(i)) >>> 0;
        }
        return palette[h % palette.length];
    }

    onSelectedTabChanged: updateFilter()

    Component.onCompleted: {
        updateFilter();
    }

    background: Rectangle {
        color: MColors.background
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header — MTopBar with search + compose actions ───────
        MTopBar {
            id: topBar
            width: parent.width
            title: "Messages"
            actions: [
                Icon {
                    name: "search"
                    size: 22
                    color: MColors.textSecondary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: {
                            HapticService.light();
                            // Search UI to be implemented as a slide-in row;
                            // tap is a no-op for now so the header chrome
                            // stays visually accurate.
                        }
                    }
                },
                // 32×32 teal-gradient compose squircle per JSX.
                Rectangle {
                    width: 32
                    height: 32
                    radius: MRadius.md
                    border.width: 1
                    border.color: MColors.tealBorder
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: MColors.marathonTealBright
                        }
                        GradientStop {
                            position: 1
                            color: MColors.marathonTealDark
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: 18
                        color: "#000000"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium();
                            conversationsPage.newMessage();
                        }
                    }
                }
            ]
        }

        // ── List ────────────────────────────────────────────────
        ListView {
            id: conversationsList
            width: parent.width
            height: parent.height - topBar.height - tabBar.height
            clip: true
            model: filteredConversations
            spacing: 0

            MEmptyState {
                visible: conversationsList.count === 0
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "message-circle"
                title: conversationsPage.selectedTab === "pinned" ? "No pinned conversations" : conversationsPage.selectedTab === "archive" ? "Archive is empty" : "No conversations yet"
                message: "Tap the + in the header to start a new conversation"
            }

            delegate: Item {
                width: conversationsList.width
                height: 70

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
                        color: conversationsPage.tintFor(modelData.contactName || modelData.contactNumber || "?")
                        border.width: 1
                        border.color: MColors.whiteOverlay08

                        Text {
                            anchors.centerIn: parent
                            text: conversationsPage.monogramOf(modelData.contactName || modelData.contactNumber || "·")
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: 15
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

                            Text {
                                id: nameText
                                anchors.left: parent.left
                                anchors.right: timeText.left
                                anchors.rightMargin: 8
                                text: modelData.contactName || modelData.contactNumber || "Unknown"
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
                                text: modelData.lastMessageTime || ""
                                color: (modelData.unreadCount || 0) > 0 ? MColors.marathonTealBright : MColors.textSecondary
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
                                text: modelData.lastMessage || ""
                                color: MColors.textSecondary
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
                                visible: (modelData.unreadCount || 0) > 0
                                width: badgeText.implicitWidth + 14

                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: String(modelData.unreadCount || 0)
                                    color: "#000000"
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
                        conversationsPage.openConversation(modelData.id || modelData.contactNumber || "");
                    }
                    onPressAndHold: {
                        HapticService.medium();
                        contextMenu.conversationId = modelData.id;
                        contextMenu.isUnread = (modelData.unreadCount || 0) > 0;
                        contextMenu.visible = true;
                    }
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
                    "icon": "star"
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

    MSheet {
        id: contextMenu

        property string conversationId: ""
        property bool isUnread: false

        visible: false
        title: "Conversation Options"

        Column {
            width: parent.width
            spacing: 0

            MSettingsListItem {
                title: contextMenu.isUnread ? "Mark as Read" : "Mark as Unread"
                iconName: contextMenu.isUnread ? "check" : "circle"
                showChevron: false
                onSettingClicked: {
                    if (contextMenu.isUnread)
                        SMSService.markAsRead(contextMenu.conversationId);
                    HapticService.light();
                    contextMenu.visible = false;
                }
            }

            MSettingsListItem {
                title: "Delete Conversation"
                iconName: "trash"
                showChevron: false
                onSettingClicked: {
                    deleteConversation(contextMenu.conversationId);
                    HapticService.medium();
                    contextMenu.visible = false;
                }
            }
        }
    }
}
