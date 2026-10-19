import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica
import "../../shell/qml/components"
import "../../shell/qml/core/LauncherGrid.js" as LauncherGrid

// The grid is laid out for the window it is in, which on a development host
// or in the simulator is not the screen (Constants.screenWidth here is 360).
TestCase {
    name: "AppGridSize"
    when: windowShown

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        MarathonAppGrid {
            id: grid

            anchors.fill: parent
        }
    }

    function test_columnsAndRowsFollowTheWindow() {
        compare(grid.columns, LauncherGrid.columns(540, Silica.Theme.pixelRatio, 0));
        compare(grid.rows, LauncherGrid.rows(1140, Silica.Theme.iconSizeLauncher));
        verify(grid.columns !== LauncherGrid.columns(Constants.screenWidth, Silica.Theme.pixelRatio, 0));
    }
}
