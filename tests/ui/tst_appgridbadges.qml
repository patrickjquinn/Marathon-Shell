import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "AppGridBadges"
    when: windowShown

    Window {
        id: win

        width: 360
        height: 1140
        visible: true

        MarathonAppGrid {
            id: grid

            anchors.fill: parent
            appModel: QtObject {
                readonly property var apps: [
                    {
                        "id": "phone",
                        "name": "Phone",
                        "icon": ""
                    },
                    {
                        "id": "mail",
                        "name": "Mail",
                        "icon": ""
                    },
                    {
                        "id": "clock",
                        "name": "Clock",
                        "icon": ""
                    }
                ]
                readonly property int count: apps.length
                function getAppAtIndex(i) {
                    return apps[i] || null;
                }
            }
        }
    }

    function init() {
        NotificationService.notifications = [];
        SettingsManagerCpp.showNotificationBadges = true;
    }

    function test_noOverlaysWithoutNotifications() {
        compare(grid.badges.length, 0);
    }

    function test_badgeFollowsNewNotifications() {
        NotificationService.notifications = [
            {
                "appId": "mail",
                "read": false
            },
            {
                "appId": "mail",
                "read": false
            }
        ];
        compare(grid.badges.length, 1);
        compare(grid.badges[0].index, 1);
        compare(grid.badges[0].count, 2);

        NotificationService.notifications = [
            {
                "appId": "mail",
                "read": true
            }
        ];
        compare(grid.badges.length, 0);
    }

    function test_badgesOffInSettings() {
        NotificationService.notifications = [
            {
                "appId": "clock",
                "read": false
            }
        ];
        SettingsManagerCpp.showNotificationBadges = false;
        compare(grid.badges.length, 0);
    }
}
