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

    function test_tapOpensTheNotificationsApp() {
        addNotification(42, "messages");
        tryVerify(() => row(0));
        mouseClick(row(0));
        compare(NotificationService.clicked, [42]);
        compare(NotificationModel.read, [42]);
        compare(NavigationRouter.deepLinks.length, 1);
        compare(NavigationRouter.deepLinks[0].appId, "messages");
        compare(NavigationRouter.deepLinks[0].params.notificationId, 42);
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
}
