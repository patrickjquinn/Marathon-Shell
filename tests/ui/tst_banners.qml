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

        ErrorToast {
            id: errorToast
        }

        ConnectionToast {
            id: connectionToast
        }
    }

    readonly property real bannerY: Constants.statusBarHeight + 20

    function init() {
        NavigationRouter.deepLinks = [];
        NotificationService.clicked = [];
        NotificationService.triggered = [];
        underneath.taps = 0;
    }

    function cleanup() {
        notificationToast.dismissToast();
        tryVerify(() => !notificationToast.currentToast);
        errorToast.hide();
        connectionToast.hide();
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

    // NotificationHandler opens the app on the click; the banner must not too.
    function test_tapOnMessageClicksItOnce() {
        notificationToast.showToast(message([]));
        wait(50);
        verify(!notificationToast.canReply);
        mouseClick(win.contentItem, 40, bannerY);
        compare(NavigationRouter.deepLinks.length, 0);
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
        compare(NotificationService.clicked, [7]);
    }

    function bannerIcon() {
        return findChild(notificationToast, "bannerIcon");
    }

    readonly property string redPixels: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGP4z8DwHxkzkC4AADxAH+HggXe0AAAAAElFTkSuQmCC"

    // app_icon / image hints by glyph, theme name or picture; then the
    // freedesktop category; then the bell.
    function test_bannerShowsTheNotificationsIcon() {
        const show = (icon, category) => {
            const n = message([]);
            n.icon = icon;
            n.category = category;
            if (notificationToast.currentToast)
                notificationToast.dismissToast();
            notificationToast.showToast(n);
            tryVerify(() => notificationToast.currentToast === n);
        };
        show("message-circle", "message");
        compare(bannerIcon().glyph, "message-circle");
        show(redPixels, "");
        tryVerify(() => bannerIcon().hasImage);
        show("", "email.arrived");
        compare(bannerIcon().glyph, "mail");
        show("", "");
        compare(bannerIcon().glyph, "bell");
        verify(!bannerIcon().hasImage);
    }

    function titled(id, title, urgency) {
        return {
            "id": id,
            "appId": "test",
            "title": title,
            "body": "",
            "urgency": urgency,
            "actions": []
        };
    }

    // Hides the banner on screen and returns the title of the next one.
    function nextBanner() {
        const before = notificationToast.currentToast;
        notificationToast.dismissToast();
        tryVerify(() => notificationToast.currentToast !== before);
        return notificationToast.currentToast ? notificationToast.currentToast.title : null;
    }

    // As the OEM test app posts them: simple, icon, critical, actions.
    function test_everyBannerShowsCriticalFirst() {
        notificationToast.showToast(titled(1, "Simple", 1));
        notificationToast.showToast(titled(2, "Icon", 1));
        notificationToast.showToast(titled(3, "Important", 2));
        notificationToast.showToast(titled(4, "Interactive", 1));
        notificationToast.showToast(titled(5, "Also important", 2));
        compare(notificationToast.currentToast.title, "Simple");
        compare(nextBanner(), "Important");
        compare(nextBanner(), "Also important");
        compare(nextBanner(), "Icon");
        compare(nextBanner(), "Interactive");
        compare(nextBanner(), null);
    }

    function test_closedNotificationLosesItsBanner() {
        notificationToast.showToast(titled(1, "Simple", 1));
        notificationToast.showToast(titled(2, "Closed", 1));
        notificationToast.showToast(titled(3, "Kept", 1));
        NotificationService.notificationDismissed(2);
        compare(nextBanner(), "Kept");
        NotificationService.notificationDismissed(3);
        verify(!notificationToast.shown);
        tryVerify(() => !notificationToast.currentToast);
    }

    // The banner's button, once its row is laid out.
    function bannerButton(key) {
        const row = findChild(notificationToast, "bannerActions");
        waitForPolish(row.parent);
        waitForPolish(row);
        return findChild(row, "notificationAction-" + key);
    }

    // Up to three buttons; "default" is the body tap, not a button.
    function test_actionButtons() {
        notificationToast.showToast(message([{
                "key": "default",
                "label": "Open"
            }, {
                "key": "reply",
                "label": "Reply"
            }, {
                "key": "dismiss",
                "label": "Dismiss"
            }, {
                "key": "snooze",
                "label": "Snooze"
            }, {
                "key": "later",
                "label": "Later"
            }]));
        const row = findChild(notificationToast, "bannerActions");
        compare(row.buttons.map(b => b.key), ["reply", "dismiss", "snooze"]);
        verify(row.visible);
        mouseClick(bannerButton("snooze"));
        compare(NotificationService.triggered, ["7:snooze"]);
        compare(NotificationService.clicked, []);
        verify(!notificationToast.shown);
    }

    // A missed call's actions, as TelephonyIntegration names them.
    function test_shellNotificationActionsById() {
        notificationToast.showToast(message([{
                "id": "call_back",
                "label": "Call Back"
            }, {
                "id": "message",
                "label": "Message"
            }]));
        mouseClick(bannerButton("call_back"));
        compare(NotificationService.triggered, ["7:call_back"]);
    }

    function test_replyLeadsTheButtonsAndOpensTheField() {
        notificationToast.showToast(message([{
                "key": "inline-reply",
                "label": "Reply"
            }, {
                "key": "mark-read",
                "label": "Mark read"
            }]));
        const row = findChild(notificationToast, "bannerActions");
        compare(row.buttons.map(b => b.key), ["inline-reply", "mark-read"]);
        mouseClick(bannerButton("inline-reply"));
        verify(notificationToast.showInlineReply);
        verify(!row.visible);
        compare(NotificationService.triggered, []);
    }

    // With action-icons the key names the icon; a name with no icon keeps
    // its label.
    function test_actionIconsOnlyWhenHinted() {
        const n = message([{
                "key": "phone",
                "label": "Call back"
            }, {
                "key": "frobnicate",
                "label": "Frobnicate"
            }]);
        notificationToast.showToast(n);
        const row = findChild(notificationToast, "bannerActions");
        verify(!findChild(row, "notificationAction-phone").iconOnly);
        notificationToast.dismissToast();
        const hinted = message(n.actions);
        hinted.actionIcons = true;
        notificationToast.showToast(hinted);
        tryVerify(() => notificationToast.currentToast === hinted);
        tryVerify(() => findChild(row, "notificationAction-phone").iconOnly);
        verify(!findChild(row, "notificationAction-frobnicate").iconOnly);
    }

    function test_swipeUpDismissesWithoutOpening() {
        notificationToast.showToast(message([]));
        wait(50);
        swipeUp(40, bannerY);
        verify(!notificationToast.shown);
        compare(NavigationRouter.deepLinks.length, 0);
    }

    function test_errorToastLetsTapsThrough() {
        errorToast.show("Battery low", "10% left", "battery-low");
        wait(50);
        mouseClick(win.contentItem, win.width / 2, win.height / 2);
        compare(underneath.taps, 1);
        verify(errorToast.shown);
    }

    function test_errorToastSwipesUp() {
        errorToast.show("Battery low", "10% left", "battery-low");
        wait(50);
        mousePress(win.contentItem, 40, bannerY);
        mouseMove(win.contentItem, 40, bannerY + 40);
        mouseMove(win.contentItem, 40, bannerY + 80);
        mouseRelease(win.contentItem, 40, bannerY + 80);
        verify(errorToast.shown);
        swipeUp(40, bannerY);
        verify(!errorToast.shown);
        compare(underneath.taps, 0);
    }

    function test_connectionToastSwipesUp() {
        connectionToast.show("Connected to Home", "wifi");
        wait(50);
        swipeUp(win.width / 2, bannerY);
        verify(!connectionToast.shown);
    }
}
