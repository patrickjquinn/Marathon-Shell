import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../Marathon/Silica/Fling.js" as Fling

TestCase {
    id: testCase

    name: "Fling"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: flickable

        SilicaFlickable {
            width: 540
            height: 960
            contentHeight: 10000
        }
    }

    Component {
        id: list

        SilicaListView {
            width: 540
            height: 960
            model: 120
            delegate: Item {
                width: 540
                height: 80
            }
        }
    }

    Component {
        id: pressList

        SilicaListView {
            property bool rowHighlighted: false
            property bool rowClicked: false
            readonly property Item row: itemAtIndex(7)

            width: 540
            height: 960
            model: 120
            delegate: ListItem {
                width: 540
                contentHeight: 80
                onHighlightedChanged: if (highlighted) ListView.view.rowHighlighted = true
                onClicked: ListView.view.rowClicked = true
            }
        }
    }

    Component {
        id: grid

        SilicaGridView {
            width: 540
            height: 960
            cellWidth: 270
            cellHeight: 80
            model: 240
            delegate: Item {
                width: 270
                height: 80
            }
        }
    }

    function views_data() {
        return [{
                tag: "flickable",
                view: flickable
            }, {
                tag: "list",
                view: list
            }, {
                tag: "grid",
                view: grid
            }];
    }

    function test_androidPhysics_data() {
        return views_data();
    }

    function test_androidPhysics(data) {
        const v = createTemporaryObject(data.view, testCase);
        compare(v.flickDeceleration, Fling.deceleration * Theme.pixelRatio);
        compare(v.maximumFlickVelocity, Fling.maxVelocity * Theme.pixelRatio);
    }

    function test_pressStopsAFling_data() {
        return views_data();
    }

    function test_pressStopsAFling(data) {
        const v = createTemporaryObject(data.view, testCase);
        v.flick(0, -6000);
        tryVerify(() => v.flicking);
        wait(50);
        mousePress(v, 270, 480);
        verify(!v.flicking);
        const y = v.contentY;
        wait(100);
        compare(v.contentY, y);
        mouseRelease(v, 270, 480);
    }

    function test_flingStopsAtTheEnd_data() {
        return views_data();
    }

    function test_flingStopsAtTheEnd(data) {
        const v = createTemporaryObject(data.view, testCase);
        v.flick(0, -Fling.maxVelocity * Theme.pixelRatio);
        tryVerify(() => !v.moving, 10000);
        verify(v.atYEnd);
        compare(v.contentY, v.originY + v.contentHeight - v.height);
        v.flick(0, Fling.maxVelocity * Theme.pixelRatio);
        tryVerify(() => !v.moving, 10000);
        verify(v.atYBeginning);
        compare(v.contentY, v.originY);
    }

    function test_scrollingNeverHighlightsARow() {
        const v = createTemporaryObject(pressList, testCase);
        // A finger rests a moment before it starts to move.
        mousePress(v, 270, 600);
        wait(60);
        for (let y = 590; y >= 400; y -= 10)
            mouseMove(v, 270, y, 8);
        mouseRelease(v, 270, 400);
        tryVerify(() => !v.moving);
        verify(!v.rowHighlighted);
    }

    function test_aHeldPressHighlights() {
        const v = createTemporaryObject(pressList, testCase);
        mousePress(v, 270, 600);
        wait(Fling.tapTimeout / 2);
        verify(!v.rowHighlighted);
        tryVerify(() => v.rowHighlighted, Fling.tapTimeout * 3);
        mouseRelease(v, 270, 600);
    }

    function test_aQuickTapClicksAndFlashes() {
        const v = createTemporaryObject(pressList, testCase);
        mouseClick(v, 270, 600);
        verify(v.rowClicked);
        const row = v.itemAt(270, 600 + v.contentY);
        verify(row._showPress);
    }

    function test_aFlingLeavesAtTheFingersSpeed_data() {
        return views_data();
    }

    // 20 px every 16 ms is 1250 px/s.
    function test_aFlingLeavesAtTheFingersSpeed(data) {
        const v = createTemporaryObject(data.view, testCase);
        let speed = 0;
        v.flickStarted.connect(() => Qt.callLater(() => speed = Math.abs(v.verticalVelocity)));
        mousePress(v, 270, 900);
        for (let y = 880; y >= 600; y -= 20)
            mouseMove(v, 270, y, 16);
        mouseRelease(v, 270, 600, Qt.LeftButton, Qt.NoModifier, 1);
        tryVerify(() => speed > 0);
        verify(speed > 1250 * 0.85 && speed < 1250 * 1.25, "left at " + speed + " px/s");
    }
}
