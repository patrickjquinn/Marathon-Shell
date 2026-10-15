import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase

    name: "FlickVelocity"

    Component {
        id: flickable

        SilicaFlickable {}
    }

    Component {
        id: list

        SilicaListView {}
    }

    Component {
        id: grid

        SilicaGridView {}
    }

    function test_jollaVelocity_data() {
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

    function test_jollaVelocity(data) {
        const view = createTemporaryObject(data.view, testCase);
        verify(Theme.pixelRatio > 0);
        compare(view.maximumFlickVelocity, 7500 * Theme.pixelRatio);
    }
}
