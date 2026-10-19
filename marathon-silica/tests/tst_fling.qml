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
}
