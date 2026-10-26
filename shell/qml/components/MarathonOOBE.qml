pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Shapes
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "oobe"

// First-run setup: one beat at a time over the wallpaper, driven by the
// real nav bar. Back asks the beat first, then goes one beat back.
Item {
    id: oobeRoot

    // 0 Hello, 1 Get online, 2 Keep it private, 3 Make it yours,
    // 4 Easy to read, 5 Your Hub, 6 Off you go.
    property int beat: 0
    readonly property var beats: [hello, online, passcode, look, size, hub, finishBeat]

    signal setupComplete

    function advance() {
        if (beat < beats.length - 1)
            ++beat;
    }

    function back() {
        const current = beats[beat];
        if (typeof current.handleBack === "function" && current.handleBack())
            return;
        if (beat > 0)
            --beat;
    }

    function finish() {
        // Before firstRunComplete: setting it unloads setup.
        setupComplete();
        SettingsManagerCpp.firstRunComplete = true;
    }

    // Swipe up, a tap on the bar or Enter: starts setup on Hello, ends it on
    // the last beat, and does nothing in between.
    function begin() {
        if (beat === 0) {
            HapticManager.light();
            advance();
        } else if (beat === beats.length - 1) {
            HapticManager.medium();
            finish();
        }
    }

    anchors.fill: parent
    visible: !SettingsManagerCpp.firstRunComplete
    z: Constants.zIndexModalOverlay

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        preventStealing: true
        onPressed: function (mouse) {
            mouse.accepted = true;
        }
        onWheel: function (wheel) {
            wheel.accepted = true;
        }
    }

    WallpaperReveal {
        id: backdrop

        objectName: "oobeBackdrop"
        anchors.fill: parent
        // Detached from the setting: Make it yours drives it through reveal().
        Component.onCompleted: current = SettingsManagerCpp.wallpaperPath
    }

    Rectangle {
        anchors.fill: parent
        color: AmbienceService.light ? "white" : "black"
        opacity: AmbienceService.light ? 0.45 : 0.62
    }

    Shape {
        id: glow

        width: parent.width * 1.4
        height: width
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height / 8
        opacity: 0.6

        SequentialAnimation on opacity {
            running: MMotion.gate(oobeRoot.visible && oobeRoot.beat === 0 && !SettingsManagerCpp.reduceMotion)
            loops: Animation.Infinite

            NumberAnimation {
                to: 1
                duration: 4000
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 0.6
                duration: 4000
                easing.type: Easing.InOutSine
            }
        }

        ShapePath {
            strokeWidth: -1
            startX: 0
            startY: 0

            fillGradient: RadialGradient {
                centerX: glow.width / 2
                centerY: glow.height / 2
                centerRadius: glow.width / 2
                focalX: centerX
                focalY: centerY

                GradientStop {
                    position: 0
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.5)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }

            PathLine {
                x: glow.width
                y: 0
            }
            PathLine {
                x: glow.width
                y: glow.height
            }
            PathLine {
                x: 0
                y: glow.height
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }

    MarathonStatusBar {
        id: statusBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
    }

    OobeProgress {
        id: progress

        objectName: "oobeProgress"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: statusBar.bottom
        height: implicitHeight
        visible: oobeRoot.beat >= 1 && oobeRoot.beat <= 5
        count: 5
        current: oobeRoot.beat
    }

    Item {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: progress.bottom
        anchors.bottom: navBar.top

        OobeHello {
            id: hello

            objectName: "oobeHello"
            anchors.fill: parent
            visible: oobeRoot.beat === 0
            onDone: oobeRoot.begin()
        }

        OobeOnline {
            id: online

            objectName: "oobeOnline"
            anchors.fill: parent
            visible: oobeRoot.beat === 1
            onDone: oobeRoot.advance()
        }

        OobePasscode {
            id: passcode

            objectName: "oobePasscode"
            anchors.fill: parent
            visible: oobeRoot.beat === 2
            onDone: oobeRoot.advance()
        }

        OobeLook {
            id: look

            objectName: "oobeLook"
            anchors.fill: parent
            visible: oobeRoot.beat === 3
            onDone: oobeRoot.advance()
            onWallpaperChosen: (previous, chosen, scenePos) => {
                const p = backdrop.mapFromItem(null, scenePos.x, scenePos.y);
                backdrop.reveal(previous, chosen, p.x, p.y);
            }
        }

        OobeSize {
            id: size

            objectName: "oobeSize"
            anchors.fill: parent
            visible: oobeRoot.beat === 4
            onDone: oobeRoot.advance()
        }

        OobeHub {
            id: hub

            objectName: "oobeHub"
            anchors.fill: parent
            visible: oobeRoot.beat === 5
            onDone: oobeRoot.advance()
        }

        // Placeholder for Off you go until the finish drag lands: a swipe
        // up or a tap on the bar completes setup.
        Column {
            id: finishBeat

            objectName: "oobeFinish"
            x: Silica.Theme.horizontalPageMargin
            width: parent.width - 2 * x
            anchors.verticalCenter: parent.verticalCenter
            visible: oobeRoot.beat === 6
            spacing: Silica.Theme.paddingMedium

            Silica.Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                //: Heading of the last setup step
                text: qsTr("You're ready")
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeExtraLarge
                wrapMode: Text.Wrap
            }

            Silica.Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                //: Last setup step: how to finish
                text: qsTr("Flick the bar up, the way you began, to go home.")
                color: Silica.Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
            }
        }
    }

    MarathonNavBar {
        id: navBar

        objectName: "oobeNavBar"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        setupMode: true
        onShortSwipeUp: oobeRoot.begin()
        onLongSwipeUp: oobeRoot.begin()
        onPillTapped: oobeRoot.begin()
        onSwipeLeft: oobeRoot.back()
    }
}
