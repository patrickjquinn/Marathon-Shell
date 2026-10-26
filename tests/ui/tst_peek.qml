import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "Peek"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        MarathonPeek {
            id: peek

            anchors.fill: parent
        }
    }

    function note(id, appId, isRead) {
        NotificationService.append({
            id: id,
            appId: appId,
            title: "Ada",
            body: "Hi",
            icon: "",
            timestamp: Date.now(),
            isRead: isRead,
            ongoing: false,
            progress: -1,
            day: ""
        });
    }

    function init() {
        NotificationService.clear();
        note(1, "mail", false);
        note(2, "mail", false);
        note(3, "messages", true);
        peek.closePeek();
        tryCompare(peek, "peekProgress", 0);
    }

    // A slow pull from the edge to x, then a pause before the lift.
    function pull(x) {
        const y = peek.height / 2;
        mousePress(peek, 2, y);
        for (let i = 1; i <= 10; ++i)
            mouseMove(peek, 2 + (x - 2) * i / 10, y, 40);
        wait(100);
        mouseMove(peek, x, y + 1, 40);
        mouseRelease(peek, x, y + 1, Qt.LeftButton, Qt.NoModifier, 40);
    }

    function test_shortPullFallsBack() {
        pull(peek.iconsStop * 0.3);
        tryCompare(peek, "peekProgress", 0);
        verify(!peek.iconsShown);
    }

    function test_pullRestsOnTheIcons() {
        pull(peek.width * 0.25);
        tryVerify(() => peek.iconsShown && !peek.isFullyOpen);
        tryCompare(peek, "peekProgress", peek.iconsStop / (peek.width * 0.85));
        const icons = findChild(peek, "peekIcons");
        const at = icons.mapToItem(peek, 0, 0);
        verify(at.x >= 0 && at.x + icons.width <= peek.iconsStop + 1, "icons at " + at.x);
    }

    function test_iconsCarryBadges() {
        pull(peek.width * 0.25);
        tryVerify(() => peek.iconsShown);
        const sources = findChild(peek, "peekSources");
        compare(sources.count, 2);
        const mail = findChild(sources.itemAt(0), "peekBadge");
        verify(mail.visible);
        compare(mail.children[0].text, "2");
        verify(!findChild(sources.itemAt(1), "peekBadge").visible);
    }

    function test_tapAnIconOpensTheHubOnThatApp() {
        pull(peek.width * 0.25);
        tryVerify(() => peek.iconsShown);
        const icon = findChild(peek, "peekIcon");
        mouseClick(icon);
        tryVerify(() => peek.isFullyOpen);
        compare(findChild(peek, "peekHub").filterApp, "mail");
    }

    function test_dragOnFromTheIconsOpensTheHub() {
        pull(peek.width * 0.25);
        tryVerify(() => peek.iconsShown);
        tryCompare(peek, "peekProgress", peek.iconsStop / (peek.width * 0.85));
        const y = peek.height * 0.9;
        const x = peek.iconsStop / 2;
        mousePress(peek, x, y);
        for (let i = 1; i <= 10; ++i)
            mouseMove(peek, x + i * 40, y, 40);
        wait(100);
        mouseMove(peek, x + 400, y + 1, 40);
        mouseRelease(peek, x + 400, y + 1, Qt.LeftButton, Qt.NoModifier, 40);
        tryVerify(() => peek.isFullyOpen);
    }

    function test_longPullOpensTheHub() {
        pull(peek.width * 0.6);
        tryVerify(() => peek.isFullyOpen);
    }
}
