pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects
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
    readonly property bool lastBeat: beat === beats.length - 1
    property bool leaving: false
    property real exitShrink: 0
    // 0 full screen, 1 at 45 %: the flick on the last beat, then the way out.
    readonly property real shrink: leaving ? exitShrink : (lastBeat && !SettingsManagerCpp.reduceMotion ? navBar.gestureProgress : 0)

    signal setupComplete

    function advance() {
        if (beat < beats.length - 1)
            ++beat;
    }

    function back() {
        if (leaving)
            return;
        const current = beats[beat];
        if (typeof current.handleBack === "function" && current.handleBack())
            return;
        if (beat > 0)
            --beat;
    }

    function begin() {
        if (beat !== 0)
            return;
        HapticManager.light();
        advance();
    }

    // The home screen builds in behind setup as it goes; firstRunComplete,
    // set once it has gone, unloads it.
    function finish() {
        if (leaving)
            return;
        HapticManager.medium();
        exitShrink = shrink;
        leaving = true;
        setupComplete();
        exit.start();
    }

    // A tap on the bar: begins on Hello, goes home on the last beat.
    function pressBar() {
        if (lastBeat)
            finish();
        else
            begin();
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

    // Everything but the bar, which stays under the finger.
    Item {
        id: surface

        objectName: "oobeSurface"
        width: parent.width
        height: parent.height
        y: -oobeRoot.shrink * height / 4
        scale: 1 - 0.55 * oobeRoot.shrink
        transformOrigin: Item.Bottom
        layer.enabled: oobeRoot.shrink > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: corners
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
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

            objectName: "oobeGlow"
            width: parent.width * 1.4
            height: width
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -parent.height / 8
            opacity: 0.6

            SequentialAnimation on opacity {
                running: MMotion.gate(oobeRoot.visible && oobeRoot.beat === 0 && !SettingsManagerCpp.reduceMotion)
                loops: Animation.Infinite
                onRunningChanged: {
                    if (running)
                        glowSettle.stop();
                    else
                        glowSettle.start();
                }

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

            NumberAnimation {
                id: glowSettle

                target: glow
                property: "opacity"
                to: 0.6
                duration: MMotion.durationFor("hero")
                easing.type: Easing.InOutSine
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
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: progress.bottom
            anchors.bottom: parent.bottom
            anchors.bottomMargin: navBar.height

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

            OobeFinish {
                id: finishBeat

                objectName: "oobeFinish"
                anchors.fill: parent
                visible: oobeRoot.beat === 6
                onDone: oobeRoot.finish()
            }
        }
    }

    // The switcher card's corners, in the shrinking surface's pixels.
    Rectangle {
        id: corners

        width: surface.width
        height: surface.height
        radius: Silica.Theme.paddingMedium * oobeRoot.shrink / surface.scale
        visible: false
        layer.enabled: surface.layer.enabled
    }

    MarathonNavBar {
        id: navBar

        objectName: "oobeNavBar"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        setupMode: true
        pillAction: {
            if (oobeRoot.beat === 0)
                //: Screen reader name of the bar on the first setup screen
                return qsTr("Begin setup");
            if (oobeRoot.lastBeat)
                //: Screen reader name of the bar on the last setup screen
                return qsTr("Go home");
            return "";
        }
        onShortSwipeUp: oobeRoot.begin()
        onLongSwipeUp: oobeRoot.begin()
        onMinimizeApp: {
            if (oobeRoot.lastBeat)
                oobeRoot.finish();
        }
        onMinimizeCancelled: {
            if (oobeRoot.beat === 0)
                ++hello.failedTries;
            else if (oobeRoot.lastBeat)
                ++finishBeat.failedTries;
        }
        onPillTapped: oobeRoot.pressBar()
        onSwipeLeft: oobeRoot.back()
    }

    // Reduce motion: a cross-fade, the surface left at full size.
    ParallelAnimation {
        id: exit

        readonly property int length: SettingsManagerCpp.reduceMotion ? MMotion.normal : MMotion.moderate

        onFinished: SettingsManagerCpp.firstRunComplete = true

        NumberAnimation {
            target: oobeRoot
            property: "exitShrink"
            to: SettingsManagerCpp.reduceMotion ? 0 : 1
            duration: exit.length
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: oobeRoot
            property: "opacity"
            to: 0
            duration: exit.length
            easing.type: Easing.OutCubic
        }
    }
}
