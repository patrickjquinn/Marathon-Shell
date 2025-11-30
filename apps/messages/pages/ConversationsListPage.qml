import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Feedback
import MarathonUI.Modals
import MarathonUI.Navigation
import "../components"

Page {
    id: conversationsPage

    signal openConversation(string conversationId)
    signal newMessage

    property var filteredConversations: messagesApp.conversations
    property bool showUnreadOnly: false
    property string searchQuery: ""

    background: Rectangle {
        color: MColors.background
    }

    Component.onCompleted: {
        updateFilter();
    }

    Column {
        anchors.fill: parent
        spacing: 0

        MActionBar {
            id: actionBar
            showBack: false
            width: parent.width

            onSignatureClicked: {
                HapticService.medium();
                newMessage();
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: MSpacing.md
                anchors.verticalCenter: parent.verticalCenter
                width: titleText.width
                height: titleText.height
                color: "transparent"

                MLabel {
                    id: titleText
                    text: "Messages"
                    variant: "primary"
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightBold
                }
            }
        }

        Item {
            id: searchBar
            width: parent.width
            height: searchInput.visible ? 60 : 0
            visible: height > 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: MMotion.fast
                    easing.bezierCurve: MMotion.easingStandardCurve
                }
            }

            Rectangle {
                anchors.fill: parent
                color: MColors.surface

                MTextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.margins: MSpacing.md
                    placeholderText: "Search conversations..."
                    visible: false

                    onTextChanged: {
                        searchQuery = text;
                        searchTimer.restart();
                    }

                    Timer {
                        id: searchTimer
                        interval: 300
                        onTriggered: updateFilter()
                    }
                }
            }
        }

        Item {
            id: filterRow
            width: parent.width
            height: 52

            Rectangle {
                anchors.fill: parent
                color: MColors.surface

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: MColors.border
                }

                Row {
                    anchors.centerIn: parent
                    spacing: MSpacing.sm

                    MButton {
                        text: "All"
                        variant: !showUnreadOnly ? "primary" : "ghost"
                        onClicked: {
                            showUnreadOnly = false;
                            updateFilter();
                            HapticService.light();
                        }
                    }

                    MButton {
                        text: "Unread"
                        variant: showUnreadOnly ? "primary" : "ghost"
                        onClicked: {
                            showUnreadOnly = true;
                            updateFilter();
                            HapticService.light();
                        }
                    }
                }
            }
        }

        ScrollView {
            width: parent.width
            height: parent.height - actionBar.height - filterRow.height - searchBar.height
            contentWidth: width
            clip: true

            ListView {
                id: conversationsList
                anchors.fill: parent
                topMargin: MSpacing.md
                bottomMargin: MSpacing.md
                spacing: MSpacing.sm

                model: filteredConversations

                delegate: Item {
                    width: conversationsList.width
                    height: 88

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - MSpacing.md * 2
                        height: parent.height

                        Rectangle {
                            id: deleteButton
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 80
                            color: MColors.error
                            radius: MRadius.lg
                            visible: conversationItem.x < -20
                            opacity: Math.min(1, Math.abs(conversationItem.x) / 80)

                            Icon {
                                anchors.centerIn: parent
                                name: "trash"
                                size: Constants.iconSizeMedium
                                color: "#FFFFFF"
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.heavy();
                                    deleteConversation(modelData.id);
                                }
                            }
                        }

                        ConversationListItem {
                            id: conversationItem
                            anchors.fill: parent
                            conversation: modelData

                            Behavior on x {
                                NumberAnimation {
                                    duration: MMotion.fast
                                    easing.bezierCurve: MMotion.easingStandardCurve
                                }
                            }

                            onConversationClicked: {
                                if (conversationItem.x === 0) {
                                    openConversation(modelData.id);
                                } else {
                                    conversationItem.x = 0;
                                }
                            }
                        }

                        MouseArea {
                            id: swipeArea
                            anchors.fill: parent
                            z: -1

                            property real startX: 0
                            property bool longPressActive: false

                            onPressed: mouse => {
                                startX = mouse.x;
                                longPressActive = false;
                                HapticService.light();
                            }

                            onPressAndHold: {
                                longPressActive = true;
                                HapticService.medium();
                                contextMenu.conversationId = modelData.id;
                                contextMenu.isUnread = modelData.unreadCount > 0;
                                contextMenu.visible = true;
                            }

                            onPositionChanged: mouse => {
                                if (pressed && !longPressActive) {
                                    var delta = mouse.x - startX;
                                    if (delta < 0) {
                                        conversationItem.x = Math.max(delta, -80);
                                    }
                                }
                            }

                            onReleased: mouse => {
                                if (!longPressActive) {
                                    if (conversationItem.x < -40) {
                                        conversationItem.x = -80;
                                    } else {
                                        conversationItem.x = 0;
                                    }
                                }
                            }

                            onCanceled: {
                                conversationItem.x = 0;
                            }
                        }
                    }
                }

                MEmptyState {
                    visible: conversationsList.count === 0
                    anchors.centerIn: parent
                    width: parent.width - MSpacing.xl * 2
                    iconName: "message-circle"
                    title: searchQuery.length > 0 ? "No conversations found" : (showUnreadOnly ? "No unread messages" : "No conversations yet")
                    message: searchQuery.length > 0 ? "Try a different search term" : "Start a new conversation to begin messaging"
                }
            }
        }
    }

    MCircularIconButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.lg
        iconName: "plus"
        iconSize: 28
        variant: "primary"
        buttonSize: 62
        onClicked: {
            HapticService.medium();
            newMessage();
        }
    }

    MSheet {
        id: contextMenu
        visible: false

        property string conversationId: ""
        property bool isUnread: false

        title: "Conversation Options"

        Column {
            width: parent.width
            spacing: 0

            MSettingsListItem {
                title: contextMenu.isUnread ? "Mark as Read" : "Mark as Unread"
                iconName: contextMenu.isUnread ? "check" : "circle"
                showChevron: false
                onSettingClicked: {
                    if (typeof SMSService !== 'undefined') {
                        if (contextMenu.isUnread) {
                            SMSService.markAsRead(contextMenu.conversationId);
                        }
                    }
                    HapticService.light();
                    contextMenu.visible = false;
                }
            }

            MSettingsListItem {
                title: "Open Conversation"
                iconName: "message-circle"
                showChevron: false
                onSettingClicked: {
                    openConversation(contextMenu.conversationId);
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

    function updateFilter() {
        var conversations = messagesApp.conversations;

        if (showUnreadOnly) {
            conversations = conversations.filter(function (c) {
                return c.unreadCount > 0;
            });
        }

        if (searchQuery.length > 0) {
            var query = searchQuery.toLowerCase();
            conversations = conversations.filter(function (c) {
                return (c.contactName && c.contactName.toLowerCase().includes(query)) || (c.contactNumber && c.contactNumber.includes(query)) || (c.lastMessage && c.lastMessage.toLowerCase().includes(query));
            });
        }

        filteredConversations = conversations;
    }

    function deleteConversation(conversationId) {
        if (typeof SMSService !== 'undefined') {
            SMSService.deleteConversation(conversationId);
        }
    }
}
