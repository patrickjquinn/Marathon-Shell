import QtQuick
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "ShellOrientation"

    QtObject {
        id: shell

        property string state: "home"
    }

    QtObject {
        id: compositor

        property var turns: []

        function setOutputOrientation(orientation) {
            turns = turns.concat([orientation]);
        }
    }

    ShellInitialization {
        id: init

        shell: shell
        compositor: compositor
    }

    function init() {
        Display.rotationLocked = false;
        Display.orientation = "portrait";
        shell.state = "home";
        compositor.turns = [];
    }

    function test_theShellStaysUpright() {
        for (const state of ["home", "locked", "pinEntry"]) {
            shell.state = state;
            Display.orientation = "landscape";
            compare(init.orientation, "portrait", state);
            Display.orientation = "portrait";
        }
        compare(compositor.turns, []);
    }

    function test_anAppTurnsWithThePhone() {
        shell.state = "app";
        Display.orientation = "landscape";
        compare(init.orientation, "landscape");
        Display.orientation = "landscape-inverted";
        compare(compositor.turns, ["landscape", "landscape-inverted"]);
    }

    function test_leavingTheAppTurnsTheShellBack() {
        shell.state = "app";
        Display.orientation = "landscape";
        shell.state = "home";
        compare(compositor.turns, ["landscape", "portrait"]);
        shell.state = "app";
        compare(init.orientation, "landscape");
    }

    function test_theRotationLockKeepsAppsUpright() {
        Display.rotationLocked = true;
        shell.state = "app";
        Display.orientation = "landscape";
        compare(init.orientation, "portrait");
        Display.rotationLocked = false;
        compare(init.orientation, "landscape");
    }
}
