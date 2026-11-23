import QtQuick
import QtQuick.Window
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../../shell/qml/components"
import "../../../shell/qml/core" as Core
import "../../../shell/qml/keyboard/Core"

// The e-ink mode mockups: the shell's own components at the MP01's 600x800
// in the e-ink palette.
// render-mockups.sh runs it; arguments after "--": the output directory,
// then "eink" or "lcd".
Window {
    id: win

    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property string out: args[0] || "."
    readonly property bool eink: args[1] !== "lcd"
    // Each view, and the waveform the panel would draw it with.
    readonly property var shots: [
        {
            name: "lock",
            view: lockView,
            fast: false
        },
        {
            name: "home",
            view: homeView,
            fast: false
        },
        {
            name: "home-fast",
            view: homeView,
            fast: true
        },
        {
            name: "switcher",
            view: switcherView,
            fast: false
        },
        {
            name: "quicksettings",
            view: quickSettingsView,
            fast: false
        },
        {
            name: "keyboard",
            view: keyboardView,
            fast: false
        }
    ]
    property int shot: -1

    width: 600
    height: 800
    visible: true
    color: MColors.background

    function next() {
        if (++shot >= shots.length) {
            Qt.quit();
            return;
        }
        Display.refreshMode = shots[shot].fast ? "fast" : "quality";
        stage.sourceComponent = shots[shot].view;
        grabTimer.start();
    }

    Component.onCompleted: {
        MColors.eink = eink;
        MMotion.instant = eink;
        Display.refreshControls = eink;
        UIStore.shellRef = shellStub;
        ambience.active = true;
        next();
    }

    Loader {
        id: ambience

        active: false
        sourceComponent: Core.AmbienceController {
            service: QtObject {
                property color baseColor: "#3fb8af"
                property bool light: false
                property string wallpaperUrl: ""
                property real pixelRatio: 0
                signal seedChanged
                function publish(map) {
                }
            }
        }
    }

    QtObject {
        id: shellStub

        property real maxQuickSettingsHeight: 640
    }

    // The shell draws this through eink.frag; offscreen has no GPU for it,
    // so render-mockups.sh applies the same quantization (quantize.py).
    Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: MColors.background
        }

        Loader {
            id: stage

            anchors.fill: parent
        }
    }

    Timer {
        id: grabTimer

        interval: 1200
        onTriggered: win.contentItem.grabToImage(result => {
            const name = win.shots[win.shot].name + (win.eink ? "-raw" : "-lcd");
            result.saveToFile(win.out + "/" + name + ".png");
            console.log("saved", name);
            win.next();
        })
    }

    Component {
        id: lockView

        MarathonLockScreen {}
    }

    Component {
        id: homeView

        Column {
            MarathonStatusBar {
                width: parent.width
            }
            MarathonAppGrid {
                width: parent.width
                height: win.height - Constants.statusBarHeight
                appModel: QtObject {
                    readonly property var apps: [["phone", "Phone"], ["messages", "Messages"], ["email", "Mail"], ["calendar", "Calendar"], ["camera", "Camera"], ["gallery", "Gallery"], ["notes", "Notes"], ["clock", "Clock"], ["maps", "Maps"], ["music", "Music"], ["browser", "Browser"], ["calculator", "Calculator"], ["radio", "Radio"], ["terminal", "Terminal"], ["pilot", "Pilot"], ["settings", "Settings"]].map(a => ({
                                "id": a[0],
                                "name": a[1],
                                "icon": Qt.resolvedUrl("../../../apps/" + a[0] + "/assets/icon.svg").toString()
                            }))
                    readonly property int count: apps.length
                    function getAppAtIndex(i) {
                        return apps[i] || null;
                    }
                }
            }
        }
    }

    Component {
        id: switcherView

        GridView {
            anchors.fill: parent
            anchors.margins: Silica.Theme.paddingLarge
            anchors.topMargin: Constants.statusBarHeight + Silica.Theme.paddingLarge
            cellWidth: width / 2
            cellHeight: height / 2
            interactive: false
            model: ListModel {
                Component.onCompleted: {
                    for (const name of ["Messages", "Mail", "Notes", "Settings"])
                        append({
                            taskId: name,
                            appId: name.toLowerCase(),
                            title: name,
                            icon: Qt.resolvedUrl("../../../apps/" + (name === "Mail" ? "email" : name.toLowerCase()) + "/assets/icon.svg").toString(),
                            type: "marathon",
                            surfaceId: -1
                        });
                }
            }
            delegate: TaskCard {
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight
                coverSize: Qt.size(width, height * 0.8)
            }
        }
    }

    Component {
        id: quickSettingsView

        Item {
            Component.onCompleted: {
                UIStore.quickSettingsOpen = true;
                UIStore.quickSettingsHeight = 640;
            }

            MarathonQuickSettings {
                width: parent.width
                height: drawnHeight
                maxHeight: 640
            }
        }
    }

    Component {
        id: keyboardView

        Item {
            // The shell's KeyboardLayouts reads this file.
            Component.onCompleted: {
                const xhr = new XMLHttpRequest();
                xhr.open("GET", Qt.resolvedUrl("../../../shell/qml/keyboard/Layouts/languages/en_US.json"), false);
                xhr.send();
                LanguageManager.currentLayout = xhr.responseText;
                keyboardLoader.active = true;
            }

            Silica.TextArea {
                y: Constants.statusBarHeight + Silica.Theme.paddingLarge
                width: parent.width
                text: "Running late, see you at the station at half past."
                label: "Message"
            }
            Loader {
                id: keyboardLoader

                anchors.bottom: parent.bottom
                width: parent.width
                active: false
                sourceComponent: MarathonKeyboard {
                    width: parent.width
                    active: true
                }
            }
        }
    }
}
