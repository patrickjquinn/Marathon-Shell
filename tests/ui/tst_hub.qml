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
        NotificationService.triggered = [];
        AppStore.names = {};
        NavigationRouter.deepLinks = [];
        closedSpy.clear();
        hub.isInPeekMode = false;
        hub.filterApp = "";
    }

    // Every role the delegate reads, since a ListView sees only the roles
    // its first row had.
    function addNotification(id, appId, icon) {
        NotificationModel.append({ id: id, appId: appId, title: "Ada", body: "Hi", icon: icon || "", timestamp: Date.now(), isRead: false, ongoing: false, progress: -1, day: isoDay(0) });
        hub.refreshSources();
    }

    function isoDay(daysAgo) {
        const d = new Date();
        d.setDate(d.getDate() - daysAgo);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function test_dayLabels() {
        compare(hub.dayLabel(isoDay(0)), "Today");
        compare(hub.dayLabel(isoDay(1)), "Yesterday");
        const three = new Date();
        three.setDate(three.getDate() - 3);
        compare(hub.dayLabel(isoDay(3)), Qt.locale().dayName(three.getDay(), Locale.LongFormat));
        const ten = new Date();
        ten.setDate(ten.getDate() - 10);
        compare(hub.dayLabel(isoDay(10)), Qt.formatDate(ten, "d MMMM"));
    }

    function test_filtersOnlyWithMoreThanOneApp() {
        const filters = findChild(hub, "hubFilters");
        addNotification(1, "mail");
        addNotification(2, "mail");
        verify(!filters.visible);
        addNotification(3, "messages");
        verify(filters.visible);
        compare(hub.sources.map(s => s.app), ["mail", "messages"]);
        compare(hub.sources[0].unread, 2);
    }

    function test_filterNarrowsToOneApp() {
        addNotification(1, "mail");
        addNotification(2, "messages");
        addNotification(3, "mail");
        const list = findChild(hub, "hubList");
        compare(list.count, 3);
        hub.filterApp = "mail";
        tryCompare(list, "count", 2);
        hub.filterApp = "";
        tryCompare(list, "count", 3);
    }

    function test_filterClearsWhenItsAppIsGone() {
        addNotification(1, "mail");
        addNotification(2, "messages");
        hub.filterApp = "messages";
        NotificationModel.remove(1);
        hub.refreshSources();
        compare(hub.filterApp, "");
    }

    readonly property string redPixels: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGP4z8DwHxkzkC4AADxAH+HggXe0AAAAAElFTkSuQmCC"

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
        AppStore.names = { "email": "Mail" };
        addNotification(1, "email");
        addNotification(2, "signal");
        tryVerify(() => row(1));
        compare(row(0).account, "Mail");
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

    // A picture the sender sent (image-data, image-path) replaces the
    // monogram; an icon name keeps it.
    function test_rowShowsTheNotificationsPicture() {
        addNotification(1, "messages", redPixels);
        addNotification(2, "messages", "bell");
        tryVerify(() => row(1));
        tryVerify(() => findChild(row(0), "hubRowImage").hasImage);
        verify(!findChild(row(1), "hubRowImage").hasImage);
    }

    // A system notice names no sender, so its glyph stands in, as on the
    // lock screen; a message keeps its sender's monogram.
    function test_systemNotificationShowsItsGlyph() {
        NotificationModel.append({ id: 3, appId: "Software update", title: "Restart to finish updating", body: "", icon: "arrow-circle-up", timestamp: Date.now(), isRead: false });
        addNotification(4, "messages", "message-circle");
        tryVerify(() => row(1));
        verify(findChild(row(0), "hubRowImage").visible);
        verify(!findChild(row(0), "hubRowMonogram").visible);
        verify(!findChild(row(1), "hubRowImage").visible);
        verify(findChild(row(1), "hubRowMonogram").visible);
    }

    // ListModel can't hold the actions list, so the row gets it directly.
    function test_rowActionButtons() {
        addNotification(5, "messages");
        tryVerify(() => row(0));
        row(0).actions = [{
                "key": "default",
                "label": "Open"
            }, {
                "key": "snooze",
                "label": "Snooze"
            }];
        const actions = findChild(row(0), "hubRowActions");
        compare(actions.buttons.map(b => b.key), ["snooze"]);
        waitForPolish(actions);
        mouseClick(findChild(actions, "notificationAction-snooze"));
        compare(NotificationService.triggered, ["5:snooze"]);
        compare(NotificationService.clicked, []);
        mouseClick(row(0), row(0).width / 2, 10);
        compare(NotificationService.clicked, [5]);
    }

    function addProgress(id, progress) {
        NotificationModel.append({ id: id, appId: "Software update", title: "Downloading Marathon OS 26101801", body: "42%", icon: "arrow-circle-up", timestamp: Date.now(), isRead: false, ongoing: true, progress: progress });
    }

    // An ongoing row draws its progress, stays put under a swipe and
    // still opens on a tap.
    function test_ongoingRowShowsProgress() {
        addProgress(9, 0.42);
        tryVerify(() => row(0));
        verify(row(0).ongoing);
        const bar = findChild(row(0), "hubRowProgress");
        verify(bar.visible);
        const fill = findChild(row(0), "hubRowProgressFill");
        tryVerify(() => Math.abs(fill.width - fill.parent.width * 0.42) < 1);

        swipe(row(0), 0.6);
        wait(50);
        compare(NotificationService.dismissed, []);
        mouseClick(row(0));
        compare(NotificationService.clicked, [9]);
    }

    function test_unknownProgressFillsAQuarter() {
        addProgress(10, -1);
        tryVerify(() => row(0));
        const fill = findChild(row(0), "hubRowProgressFill");
        compare(fill.width, fill.parent.width / 4);
    }

    function test_plainRowHasNoProgress() {
        addNotification(11, "messages");
        tryVerify(() => row(0));
        verify(!row(0).ongoing);
        verify(!findChild(row(0), "hubRowProgress").visible);
    }

    function test_clearAll() {
        addNotification(8, "messages");
        const item = findChild(hub, "clearNotifications");
        verify(item);
        item.clicked();
        verify(NotificationService.dismissedAll);
    }
}
