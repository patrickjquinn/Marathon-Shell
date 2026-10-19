import QtQuick
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "TaskCard"
    when: windowShown
    width: 540
    height: 1140

    ListModel {
        id: tasks
    }

    GridView {
        id: grid

        anchors.fill: parent
        cellWidth: width / 2
        cellHeight: height / 2
        reuseItems: true
        model: tasks
        delegate: TaskCard {
            width: GridView.view.cellWidth
            height: GridView.view.cellHeight
            coverSize: Qt.size(width, height * 0.8)
            waylandSurface: null
        }
    }

    function cardRoot(card) {
        for (const child of card.children)
            if (child.closing !== undefined)
                return child;
        return null;
    }

    function init() {
        tasks.clear();
        for (const name of ["Feeder", "Settings"])
            tasks.append({
                id: name,
                appId: name.toLowerCase(),
                title: name,
                icon: "",
                type: "marathon",
                surfaceId: -1
            });
        tryCompare(grid, "count", 2);
    }

    // Its close takes the task, and the card goes with it: the card's
    // restore after a second must not bring a removed card's face back over
    // the one that took its place.
    function test_aRemovedCardStaysClosed() {
        tryVerify(() => grid.itemAtIndex(0) !== null);
        const card = grid.itemAtIndex(0);
        const root = cardRoot(card);
        verify(root);
        root.closing = true;
        card.closeTask();
        tasks.remove(0);
        tryCompare(grid, "count", 1);
        wait(1300);
        verify(root.closing);
        compare(root.opacity, 0);
    }
}
