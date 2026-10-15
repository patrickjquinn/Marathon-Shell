import QtQuick
import QtTest
import Keel 1.0
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "PulleyIndicator"
    when: windowShown
    visible: true
    width: 540; height: 960

    readonly property color background: "#0c2623"

    Rectangle { anchors.fill: parent; color: testCase.background }

    Component {
        id: pulleyPage
        SilicaFlickable {
            width: 540; height: 960
            contentHeight: 2000
            PullDownMenu {
                MenuItem { text: "Settings" }
                MenuItem { text: "New note" }
            }
            PushUpMenu {
                MenuItem { text: "Back to top" }
            }
        }
    }

    function sameColor(a, b) {
        return Math.abs(a.r - b.r) < 0.02 && Math.abs(a.g - b.g) < 0.02 && Math.abs(a.b - b.b) < 0.02;
    }

    function test_closedIndicatorIsFaint() {
        const f = createTemporaryObject(pulleyPage, testCase);
        verify(!f.pullDownMenu.active);
        wait(600);
        const img = grabImage(testCase);
        const solid = f.pullDownMenu.palette.highlightBackgroundColor;
        for (let y = 0; y < Theme.paddingSmall; ++y) {
            const px = Qt.color(img.pixel(width / 2, y));
            verify(!sameColor(px, solid), "row " + y + " is solid highlight " + px);
            verify(!sameColor(px, background), "row " + y + " has no indicator");
        }
    }

    function test_closedPushUpIndicatorIsFaint() {
        const f = createTemporaryObject(pulleyPage, testCase);
        f.contentY = f.contentHeight - f.height;
        tryVerify(function () { return f.atYEnd; });
        wait(600);
        const img = grabImage(testCase);
        const solid = f.pullDownMenu.palette.highlightBackgroundColor;
        let seen = false;
        for (let y = height - 1; y >= height - 2 * Theme.paddingLarge; --y) {
            const px = Qt.color(img.pixel(width / 2, y));
            verify(!sameColor(px, solid), "row " + y + " is solid highlight " + px);
            seen = seen || !sameColor(px, background);
        }
        verify(seen, "no push-up indicator");
    }

    function test_openMenuStillHighlights() {
        const f = createTemporaryObject(pulleyPage, testCase);
        f.forceActiveFocus();
        keyClick(Qt.Key_M, Qt.ControlModifier);
        tryVerify(function () { return f.pullDownMenu.active; });
        keyClick(Qt.Key_Down);
        const item = f.pullDownMenu.menuItem;
        compare(item.text, "Settings");
        verify(sameColor(f.pullDownMenu.highlightColor, f.pullDownMenu.palette.highlightBackgroundColor));
        compare(f.pullDownMenu.highlightColor.a, 1);
        wait(600);
        const p = item.mapToItem(testCase, 8, item.height / 2);
        const px = Qt.color(grabImage(testCase).pixel(p.x, p.y));
        verify(!sameColor(px, background), "highlighted item has no highlight " + px);
    }
}
