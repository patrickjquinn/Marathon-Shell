import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "Hub"
    when: windowShown

    Window {
        width: 540
        height: 1140
        visible: true

        MarathonHub {
            id: hub

            anchors.fill: parent
        }
    }

    SignalSpy {
        id: closedSpy

        target: hub
        signalName: "closed"
    }

    function init() {
        NotificationModel.clear();
        NotificationModel.read = [];
        NotificationService.clicked = [];
        NotificationService.dismissed = [];
        NotificationService.dismissedAll = false;
        AppStore.names = {};
        NavigationRouter.deepLinks = [];
        closedSpy.clear();
        hub.isInPeekMode = false;
    }

    function addNotification(id, appId) {
        NotificationModel.append({ id: id, appId: appId, title: "Ada", body: "Hi", icon: "", timestamp: Date.now(), isRead: false });
    }

    function row(i) {
        const list = findChild(hub, "hubList");
        list.forceLayout();
        return list.itemAtIndex(i);
    }

    // NotificationHandler opens the app on the click; the Hub must not too.
    function test_tapClicksTheNotificationOnce() {
        addNotification(42, "messages");
        tryVerify(() => row(0));
        mouseClick(row(0));
        compare(NotificationService.clicked, [42]);
        compare(NotificationModel.read, [42]);
        compare(NavigationRouter.deepLinks.length, 0);
    }

    function test_tapInPeekClosesIt() {
        hub.isInPeekMode = true;
        addNotification(-3, "phone");
        tryVerify(() => row(0));
        mouseClick(row(0));
        compare(NotificationService.clicked, [-3]);
        compare(closedSpy.count, 1);
    }

    function test_tapWithoutAppMarksRead() {
        addNotification(7, "");
        tryVerify(() => row(0));
        mouseClick(row(0));
        compare(NotificationModel.read, [7]);
        compare(NavigationRouter.deepLinks.length, 0);
    }

    function swipe(item, fraction) {
        const y = item.height / 2;
        mousePress(item, 2, y);
        for (let i = 1; i <= 10; i++)
            mouseMove(item, 2 + item.width * fraction * i / 10, y);
        mouseRelease(item, 2 + item.width * fraction, y);
    }

    function test_accountIsTheSendersAppName() {
        AppStore.names = { "messages": "Messages" };
        addNotification(1, "messages");
        addNotification(2, "signal");
        tryVerify(() => row(1));
        compare(row(0).account, "Messages");
        compare(row(1).account, "Signal");
    }

    function test_swipeRightDismisses() {
        addNotification(5, "messages");
        tryVerify(() => row(0));
        swipe(row(0), 0.6);
        tryCompare(NotificationService, "dismissed", [5]);
        compare(NotificationService.clicked, []);
    }

    function test_shortSwipeSnapsBack() {
        addNotification(6, "messages");
        tryVerify(() => row(0));
        swipe(row(0), 0.15);
        wait(50);
        compare(NotificationService.dismissed, []);
        compare(NotificationService.clicked, []);
    }

    function test_clearAll() {
        addNotification(8, "messages");
        const item = findChild(hub, "clearNotifications");
        verify(item);
        item.clicked();
        verify(NotificationService.dismissedAll);
    }
}
