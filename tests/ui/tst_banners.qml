import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "Banners"
    when: windowShown

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        MouseArea {
            id: underneath

            property int taps: 0

            anchors.fill: parent
            onClicked: taps++
        }

        NotificationToast {
            id: notificationToast
        }
    }

    readonly property real bannerY: Constants.statusBarHeight + 20

    function init() {
        NavigationRouter.deepLinks = [];
        NotificationService.clicked = [];
        underneath.taps = 0;
    }

    function cleanup() {
        notificationToast.dismissToast();
        wait(50);
    }

    function swipeUp(x, y) {
        mousePress(win.contentItem, x, y);
        for (let i = 1; i <= 8; i++)
            mouseMove(win.contentItem, x, y - i * 15);
        mouseRelease(win.contentItem, x, y - 120);
    }

    function message(actions) {
        return {
            "id": 7,
            "appId": "messages",
            "category": "message",
            "title": "Ana",
            "body": "Lunch?",
            "actions": actions
        };
    }

    function test_tapOnMessageOpensTheApp() {
        notificationToast.showToast(message([]));
        wait(50);
        verify(!notificationToast.canReply);
        mouseClick(win.contentItem, 40, bannerY);
        compare(NavigationRouter.deepLinks.length, 1);
        compare(NavigationRouter.deepLinks[0].appId, "messages");
        compare(NotificationService.clicked, [7]);
        verify(!notificationToast.showInlineReply);
    }

    function test_replyOnlyWhenAdvertised() {
        notificationToast.showToast(message([{
                "key": "inline-reply",
                "label": "Reply"
            }]));
        wait(50);
        verify(notificationToast.canReply);
        mouseClick(win.contentItem, 40, bannerY);
        compare(NavigationRouter.deepLinks.length, 1);
    }

    function test_swipeUpDismissesWithoutOpening() {
        notificationToast.showToast(message([]));
        wait(50);
        swipeUp(40, bannerY);
        verify(!notificationToast.shown);
        compare(NavigationRouter.deepLinks.length, 0);
    }
}
