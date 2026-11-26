import QtQuick
import QtQuick.Window
import Sailfish.Silica 1.0
import Keel 1.0 as K
import Marathon.Platform 1.0
import "../../../apps/settings"

// Settings > Display on an e-paper phone, in the ambience the shell
// publishes there (AmbienceController's einkMap). render-mockups.sh runs it.
Window {
    id: win

    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property bool eink: args[1] !== "lcd"

    width: 600
    height: 800
    visible: true
    // What the shell draws behind an app: paper on e-paper, the dark
    // ambience base otherwise (KeelAmbienceBackground).
    color: eink ? "#ffffff" : "#060b12"

    Component.onCompleted: {
        if (eink) {
            K.Ambience.applyForwarded(["/desktop/jolla/theme/color/highlight=#000000", "/desktop/jolla/theme/color/primary=#000000", "/desktop/jolla/theme/color/secondary=#444444", "/desktop/jolla/theme/color/secondary_highlight=#444444", "/desktop/jolla/theme/color/highlight_background=#000000", "/desktop/jolla/theme/color/highlight_background_opacity=0.2", "/desktop/jolla/theme/color/highlight_dimmer=#ffffff", "/desktop/jolla/theme/color/overlay_background=#ffffff", "/desktop/jolla/theme/color/error=#000000", "/desktop/jolla/theme/color_scheme=darkonlight", "/desktop/jolla/theme/wallpaper="].join("\n"));
            Display.refreshControls = true;
        }
        shot.start();
    }

    SettingsApp {
        id: app

        anchors.fill: parent
    }

    Timer {
        id: shot

        interval: 1500
        onTriggered: {
            app.openPage("display", PageStackAction.Immediate);
            grab.start();
        }
    }

    Timer {
        id: grab

        interval: 1500
        onTriggered: win.contentItem.grabToImage(result => {
            result.saveToFile(win.args[0] + "/settings-" + (win.eink ? "raw" : "lcd") + ".png");
            Qt.quit();
        })
    }
}
