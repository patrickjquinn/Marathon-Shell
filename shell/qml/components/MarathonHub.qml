import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Feedback
import MarathonUI.Modals
import "."
import MarathonUI.Theme
import MarathonUI.Navigation

Rectangle {
    id: hub
    anchors.fill: parent
    color: MColors.background

    signal closed

    property bool isInPeekMode: false
    property int selectedTabIndex: 0
    property var categoryMap: ({
            0: "all",
            1: "email",
            2: "message",
            3: "call",
            4: "social"
        })

    function filterByCategory(notification) {
        if (selectedTabIndex === 0)
            return true;

        var category = notification.category || notification.appId || "";
        var selectedCategory = categoryMap[selectedTabIndex];

        if (selectedCategory === "email" && (category.includes("mail") || category.includes("email")))
            return true;
        if (selectedCategory === "message" && (category.includes("message") || category.includes("sms") || category.includes("chat")))
            return true;
        if (selectedCategory === "call" && (category.includes("call") || category.includes("phone")))
            return true;
        if (selectedCategory === "social" && (category.includes("social") || category.includes("twitter") || category.includes("facebook")))
            return true;

        return false;
    }

    Column {
        anchors.fill: parent
        anchors.topMargin: isInPeekMode ? Constants.statusBarHeight : 0
        spacing: 0

        MTabBar {
            id: hubTabs
            width: parent.width

            tabs: [
                {
                    label: "All",
                    icon: "inbox"
                },
                {
                    label: "Email",
                    icon: "mail"
                },
                {
                    label: "Messages",
                    icon: "message-square"
                },
                {
                    label: "Calls",
                    icon: "phone"
                },
                {
                    label: "Social",
                    icon: "users"
                }
            ]

            onTabSelected: index => {
                hub.selectedTabIndex = index;
                Logger.info("Hub", "Switched to tab: " + hubTabs.tabs[index].label);
            }
        }

        Rectangle {
            id: clearBar
            width: parent.width
            height: 48
            color: MColors.surface
            visible: NotificationModel.count > 0

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: MColors.border
            }

            Row {
                anchors.centerIn: parent
                spacing: MSpacing.md

                MButton {
                    text: "Mark All Read"
                    variant: "ghost"
                    iconName: "check"
                    onClicked: {
                        HapticService.light();
                        NotificationService.markAllAsRead();
                        Logger.info("Hub", "Marked all notifications as read");
                    }
                }

                MButton {
                    text: "Clear All"
                    variant: "ghost"
                    iconName: "trash-2"
                    onClicked: {
                        HapticService.medium();
                        NotificationService.clearAll();
                        Logger.info("Hub", "Cleared all notifications");
                    }
                }
            }
        }

        ListView {
            id: notificationsList
            width: parent.width
            height: parent.height - hubTabs.height - (clearBar.visible ? clearBar.height : 0)
            clip: true
            spacing: 0

            model: NotificationModel

            delegate: Item {
                id: notificationDelegate
                width: notificationsList.width
                height: filterByCategory(model) ? 88 : 0
                visible: filterByCategory(model)
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: notificationMouseArea.pressed ? MColors.highlightSubtle : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: MMotion.quick
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: MColors.border
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: MSpacing.md
                        anchors.rightMargin: MSpacing.md
                        spacing: MSpacing.md

                        Rectangle {
                            width: 48
                            height: 48
                            radius: MRadius.md
                            color: model.isRead ? MColors.elevated : MColors.accent
                            opacity: model.isRead ? 0.5 : 0.15
                            anchors.verticalCenter: parent.verticalCenter

                            Icon {
                                name: model.icon || "bell"
                                size: 24
                                color: model.isRead ? MColors.textSecondary : MColors.accent
                                anchors.centerIn: parent
                            }
                        }

                        Column {
                            width: parent.width - 48 - 60 - MSpacing.md * 2
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: MSpacing.xs

                            Row {
                                width: parent.width
                                spacing: MSpacing.xs

                                MLabel {
                                    text: model.title
                                    variant: "primary"
                                    font.weight: model.isRead ? MTypography.weightNormal : MTypography.weightBold
                                    font.pixelSize: MTypography.sizeBody
                                    elide: Text.ElideRight
                                    width: parent.width - (unreadIndicator.visible ? unreadIndicator.width + MSpacing.xs : 0)
                                }

                                Rectangle {
                                    id: unreadIndicator
                                    visible: !model.isRead
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: MColors.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MLabel {
                                text: model.body || ""
                                variant: "secondary"
                                font.pixelSize: MTypography.sizeSmall
                                width: parent.width
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }

                        MLabel {
                            text: {
                                var now = new Date();
                                var notifDate = new Date(model.timestamp);
                                var diffMs = now - notifDate;
                                var diffMins = Math.floor(diffMs / 60000);

                                if (diffMins < 1)
                                    return "now";
                                if (diffMins < 60)
                                    return diffMins + "m";

                                var diffHours = Math.floor(diffMins / 60);
                                if (diffHours < 24)
                                    return diffHours + "h";

                                return Qt.formatDateTime(notifDate, "hh:mm");
                            }
                            variant: "tertiary"
                            font.pixelSize: MTypography.sizeXSmall
                            width: 60
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: notificationMouseArea
                        anchors.fill: parent

                        onClicked: {
                            Logger.info("Hub", "Notification clicked: " + model.title);
                            HapticService.light();
                            NotificationModel.markAsRead(model.id);

                            if (model.appId) {
                                NavigationRouter.navigateToDeepLink(model.appId, "", {
                                    "notificationId": model.id,
                                    "action": "view",
                                    "from": "hub"
                                });
                                Router.goHome();
                            }
                        }

                        onPressAndHold: {
                            Logger.info("Hub", "Long press on notification: " + model.id);
                            HapticService.medium();
                            contextMenu.open();
                        }
                    }

                    MSheet {
                        id: contextMenu
                        title: "Notification Actions"

                        Column {
                            width: parent.width
                            spacing: 0

                            MSettingsListItem {
                                title: model.isRead ? "Mark as Unread" : "Mark as Read"
                                iconName: model.isRead ? "mail" : "mail-open"
                                showChevron: false
                                onSettingClicked: {
                                    HapticService.light();
                                    if (model.isRead) {} else {
                                        NotificationModel.markAsRead(model.id);
                                    }
                                    contextMenu.close();
                                }
                            }

                            MSettingsListItem {
                                title: "Open App"
                                iconName: "external-link"
                                showChevron: false
                                visible: model.appId !== ""
                                onSettingClicked: {
                                    HapticService.light();
                                    if (model.appId) {
                                        NavigationRouter.navigateToDeepLink(model.appId, "", {});
                                        Router.goHome();
                                    }
                                    contextMenu.close();
                                }
                            }

                            MSettingsListItem {
                                title: "Delete"
                                iconName: "trash-2"
                                showChevron: false
                                onSettingClicked: {
                                    HapticService.medium();
                                    NotificationService.dismissNotification(model.id);
                                    contextMenu.close();
                                }
                            }
                        }
                    }
                }
            }

            MEmptyState {
                visible: {
                    var count = 0;
                    for (var i = 0; i < NotificationModel.count; i++) {
                        var notif = NotificationModel.data(NotificationModel.index(i, 0), 256);
                        if (filterByCategory({
                            category: notif?.category,
                            appId: notif?.appId
                        })) {
                            count++;
                        }
                    }
                    return count === 0;
                }
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "bell"
                title: "No notifications"
                message: selectedTabIndex === 0 ? "You're all caught up!" : "No " + hubTabs.tabs[selectedTabIndex].label.toLowerCase() + " notifications"
            }
        }
    }
}
