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
        id: pressGrid

        SilicaGridView {
            property bool cellClicked: false

            width: 540
            height: 960
            cellWidth: 270
            cellHeight: 300
            model: 60
            delegate: GridItem {
                width: 270
                contentHeight: 300
                onClicked: GridView.view.cellClicked = true
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

    // A press that stops a moving view only stops it, even as the fling ends.
    function test_aPressThatStopsAFlingDoesNotClick() {
        const v = createTemporaryObject(pressList, testCase);
        v.flick(0, -600);
        tryVerify(() => v.moving);
        wait(150);
        verify(v.moving);
        touchEvent(v).press(0, v, 270, 480).commit();
        wait(50);
        touchEvent(v).release(0, v, 270, 480).commit();
        verify(!v.rowClicked);
        wait(Fling.tapTimeout * 2);
        verify(!v.rowHighlighted);
        tryVerify(() => !v.moving);
        touchEvent(v).press(0, v, 270, 480).commit();
        touchEvent(v).release(0, v, 270, 480).commit();
        verify(v.rowClicked);
    }

    // Nor while it springs back from past its end.
    function test_aPressDuringTheReboundDoesNotClick() {
        const v = createTemporaryObject(pressList, testCase, {boundsBehavior: Flickable.DragAndOvershootBounds});
        v.flick(0, 4000);
        tryVerify(() => v.verticalOvershoot < 0);
        tryVerify(() => v.verticalOvershoot > -2 && v.moving, 3000, "rebounding");
        touchEvent(v).press(0, v, 270, 480).commit();
        wait(50);
        touchEvent(v).release(0, v, 270, 480).commit();
        verify(!v.rowClicked);
    }

    // And as the fling dies away below Qt's own threshold.
    function test_aPressAtTheEndOfAFlingDoesNotClick() {
        const v = createTemporaryObject(pressList, testCase);
        v.flick(0, -1500);
        tryVerify(() => v.moving && Math.abs(v.verticalVelocity) < 80, 3000);
        touchEvent(v).press(0, v, 270, 480).commit();
        wait(50);
        touchEvent(v).release(0, v, 270, 480).commit();
        verify(!v.rowClicked);
    }

    // A press that lands as the fling ends was aimed at moving content: the
    // finger came down a frame or two before the view saw it.
    function test_aPressAsTheFlingEndsDoesNotClick() {
        const v = createTemporaryObject(pressList, testCase);
        let ended = false;
        v.movementEnded.connect(() => {
            ended = true;
            touchEvent(v).press(0, v, 270, 480).commit();
            touchEvent(v).release(0, v, 270, 480).commit();
        });
        v.flick(0, -1500);
        tryVerify(() => ended, 5000);
        verify(!v.rowClicked);
        wait(Fling.flingTapGuard * 3);
        touchEvent(v).press(0, v, 270, 480).commit();
        touchEvent(v).release(0, v, 270, 480).commit();
        verify(v.rowClicked);
    }

    // The ambience picker's grid: a press as its fling ends picks nothing.
    function test_aPressAsAGridFlingEndsPicksNothing() {
        const v = createTemporaryObject(pressGrid, testCase);
        let ended = false;
        v.movementEnded.connect(() => {
            ended = true;
            touchEvent(v).press(0, v, 135, 480).commit();
            touchEvent(v).release(0, v, 135, 480).commit();
        });
        v.flick(0, -1500);
        tryVerify(() => ended, 5000);
        verify(!v.cellClicked);
        wait(Fling.flingTapGuard * 3);
        touchEvent(v).press(0, v, 135, 480).commit();
        touchEvent(v).release(0, v, 135, 480).commit();
        verify(v.cellClicked);
    }
}
