import MarathonApp.Camera 1.0
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtMultimedia 6.0

MApp {
    id: cameraApp

    property string currentMode: "photo"
    property bool flipRequested: false

    function triggerFlash() {
        flashOverlay.opacity = 1;
        flashTimer.restart();
    }

    appId: "camera"
    appName: "Camera"
    appIcon: "assets/icon.svg"
    onAppResumed: cameraController.start()
    onAppPaused: cameraController.stop()
    onAppRestored: cameraController.start()
    onAppMinimized: cameraController.stop()

    CameraController {
        id: cameraController

        onPhotoSaved: path => {
            HapticService.heavy();
            triggerFlash();
        }
        onCameraFlipStarted: cameraApp.flipRequested = !cameraApp.flipRequested
        onErrorOccurred: message => {
            return console.warn("[Camera] Error:", message);
        }
    }

    Rectangle {
        id: flashOverlay

        parent: cameraApp
        anchors.fill: parent
        color: "white"
        opacity: 0
        visible: opacity > 0
        z: 100

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.micro
            }
        }
    }

    Timer {
        id: flashTimer

        interval: 50
        onTriggered: flashOverlay.opacity = 0
    }

    content: Rectangle {
        id: contentRoot

        anchors.fill: parent
        color: "black"
        Component.onCompleted: {
            cameraController.videoSink = viewfinder.videoSink;
            cameraController.start();
        }

        Connections {
            function onFlipRequestedChanged() {
                flipAnimation.start();
            }

            target: cameraApp
        }

        SequentialAnimation {
            id: flipAnimation

            NumberAnimation {
                target: viewfinderRotation
                property: "angle"
                from: 0
                to: 90
                duration: MMotion.durationFor("hover")
                easing.type: Easing.InQuad
            }

            NumberAnimation {
                target: viewfinderRotation
                property: "angle"
                from: -90
                to: 0
                duration: MMotion.durationFor("hover")
                easing.type: Easing.OutQuad
            }
        }

        SoftwareVideoOutput {
            id: viewfinder

            anchors.fill: parent
            fillMode: SoftwareVideoOutput.PreserveAspectFit
            visible: cameraController.active

            PinchHandler {
                target: null
                onScaleChanged: delta => {
                    cameraController.zoomLevel = cameraController.zoomLevel * delta;
                }
            }

            TapHandler {
                onTapped: eventPoint => {
                    var point = eventPoint.position;
                    focusRing.x = point.x - focusRing.width / 2;
                    focusRing.y = point.y - focusRing.height / 2;
                    focusRingAnimation.restart();
                    cameraController.focusOnPoint(point.x / viewfinder.width, point.y / viewfinder.height);
                }
            }

            Rectangle {
                id: focusRing

                width: 64
                height: 64
                radius: 32
                color: "transparent"
                border.width: 2
                border.color: "#fbbf24"
                opacity: 0
                visible: opacity > 0

                SequentialAnimation {
                    id: focusRingAnimation

                    ParallelAnimation {
                        NumberAnimation {
                            target: focusRing
                            property: "scale"
                            from: 1.5
                            to: 1
                            duration: MMotion.normal
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            target: focusRing
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: MMotion.normal
                        }
                    }

                    // 500 ms hold is intentional — focus ring is meant
                    // to stay visible long enough to confirm the focus
                    // hit to the user before fading.
                    PauseAnimation {
                        duration: 500
                    }

                    NumberAnimation {
                        target: focusRing
                        property: "opacity"
                        to: 0
                        duration: MMotion.slow
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 120
                width: 60
                height: 30
                radius: 15
                color: "#80000000"
                visible: cameraController.zoomLevel > 1

                Text {
                    anchors.centerIn: parent
                    text: cameraController.zoomLevel.toFixed(1) + "x"
                    color: "white"
                    font.weight: Font.Bold
                    font.pixelSize: 14
                }
            }

            transform: Rotation {
                id: viewfinderRotation

                origin.x: viewfinder.width / 2
                origin.y: viewfinder.height / 2
                angle: 0

                axis {
                    x: 0
                    y: 1
                    z: 0
                }
            }
        }

        Text {
            anchors.centerIn: parent
            font.pixelSize: 120
            font.weight: Font.Bold
            color: "white"
            style: Text.Outline
            styleColor: "black"
            text: cameraController.timerCountdown
            visible: cameraController.timerActive && cameraController.timerCountdown > 0
        }

        Rectangle {
            anchors.fill: parent
            visible: !cameraController.active && cameraController.ready
            color: "#0f0f23"

            Column {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: cameraController.currentCameraName || "Camera"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: "#80ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "○ Initializing..."
                    font.pixelSize: 12
                    color: "#fbbf24"
                }
            }
        }

        // Empty state when zero working cameras are detected. There are two
        // valid reasons we land here:
        //
        //   1. The device genuinely has no camera (QEMU dev image, dock).
        //   2. The camera exists but Marathon never asked for permission,
        //      or the user denied it earlier. The Permission Manager
        //      re-prompts on requestPermission() so the CTA either opens
        //      the dialog fresh or surfaces the already-denied state.
        //
        // Either way, giving the user a tap target out of the dead end
        // beats showing a bare apology — same pattern as the system-wide
        // empty state work in #405 (Hub / Phone Recents / Phone Favorites).
        MEmptyState {
            anchors.centerIn: parent
            width: parent.width - MSpacing.xl * 2
            visible: cameraController.cameraCount === 0
            iconName: "camera-off"
            title: "Camera unavailable"
            message: "We couldn't find a working camera. If your device has one, Marathon may not have permission yet."
            actionText: "Grant camera access"
            onActionClicked: PermissionManager.requestPermission(cameraApp.appId, "camera")
        }

        Rectangle {
            anchors.fill: parent
            visible: cameraController.ready

            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "#40000000"
                }

                GradientStop {
                    position: 0.12
                    color: "transparent"
                }

                GradientStop {
                    position: 0.88
                    color: "transparent"
                }

                GradientStop {
                    position: 1
                    color: "#60000000"
                }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: MSpacing.lg + 48
            width: 120
            height: 40
            radius: 20
            color: "#c0000000"
            visible: cameraController.isRecording
            z: 10

            Row {
                anchors.centerIn: parent
                spacing: MSpacing.sm

                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: "#ff4444"
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on opacity {
                        running: cameraController.isRecording
                        loops: Animation.Infinite

                        // 1-second total pulse (500 ms each way) is the
                        // recording-indicator's intended rhythm; do NOT
                        // migrate to MMotion role durations — those are
                        // tuned for one-shot microinteractions, not
                        // infinite attention loops.
                        NumberAnimation {
                            from: 1
                            to: 0.2
                            duration: 500
                        }

                        NumberAnimation {
                            from: 0.2
                            to: 1
                            duration: 500
                        }
                    }
                }

                Text {
                    text: {
                        var mins = Math.floor(cameraController.recordingDuration / 60);
                        var secs = cameraController.recordingDuration % 60;
                        return mins + ":" + (secs < 10 ? "0" : "") + secs;
                    }
                    font.pixelSize: 18
                    font.bold: true
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Top control row (JSX ref-camera) ─────────────────
        // Flash circle (left) · HDR · ON pill (centre) · Settings gear
        // (right). All sit on the viewfinder with a subtle dark fill +
        // tealBorder ring when the corresponding state is active.
        Item {
            id: cameraTopBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 20
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            height: 44
            z: 10
            visible: cameraController.ready

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.55)
                border.width: 1
                border.color: cameraController.flashEnabled ? MColors.tealBorder : MColors.whiteOverlay08
                visible: cameraController.flashAvailable

                // Flash glyph morph — crossfade between zap (on) and
                // zap-off (off) Icons. Direct name binding caused a
                // visible glyph-atlas reload flicker when toggling.
                Item {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    Icon {
                        anchors.centerIn: parent
                        name: "zap"
                        size: 20
                        color: MColors.marathonTealBright
                        opacity: cameraController.flashEnabled ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: MMotion.durationFor("tap")
                            }
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: "zap-off"
                        size: 20
                        color: MColors.textSecondary
                        opacity: cameraController.flashEnabled ? 0 : 1
                        Behavior on opacity {
                            NumberAnimation {
                                duration: MMotion.durationFor("tap")
                            }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        cameraController.flashEnabled = !cameraController.flashEnabled;
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: width / 2
                color: Qt.rgba(0, 0, 0, 0.55)
                border.width: 1
                border.color: MColors.whiteOverlay08

                Icon {
                    anchors.centerIn: parent
                    name: "settings"
                    size: 20
                    color: MColors.textSecondary
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        settingsSheet.show();
                    }
                }
            }
        }

        // ── Rule-of-thirds grid overlay (JSX ref-camera) ─────
        // Two vertical and two horizontal hairlines, 8% alpha so the
        // viewfinder dominates. Drawn above the camera surface.
        Item {
            id: cameraGrid
            anchors.fill: parent
            anchors.topMargin: cameraTopBar.height + 40
            anchors.bottomMargin: 220
            z: 8
            visible: cameraController.ready

            Rectangle {
                width: 1
                height: parent.height
                x: parent.width / 3
                color: Qt.rgba(1, 1, 1, 0.18)
            }
            Rectangle {
                width: 1
                height: parent.height
                x: parent.width * 2 / 3
                color: Qt.rgba(1, 1, 1, 0.18)
            }
            Rectangle {
                height: 1
                width: parent.width
                y: parent.height / 3
                color: Qt.rgba(1, 1, 1, 0.18)
            }
            Rectangle {
                height: 1
                width: parent.width
                y: parent.height * 2 / 3
                color: Qt.rgba(1, 1, 1, 0.18)
            }
        }

        // ── Mode strip (JSX ref-camera) ─────────────────────
        // 5 modes in a horizontal strip; active mode gets teal-bright
        // colour + a 2 px teal underline. SLO-MO / PORTRAIT / PANO are
        // surfaced visually but degrade to the closest cameraController
        // mode (photo/video) on tap until the engine supports them.
        Row {
            id: modeStrip
            anchors.bottom: bottomControls.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 18
            spacing: 28
            z: 10
            visible: cameraController.ready

            Repeater {
                model: [
                    {
                        label: "SLO-MO",
                        mode: "video"
                    },
                    {
                        label: "VIDEO",
                        mode: "video"
                    },
                    {
                        label: "PHOTO",
                        mode: "photo"
                    },
                    {
                        label: "PORTRAIT",
                        mode: "photo"
                    },
                    {
                        label: "PANO",
                        mode: "photo"
                    }
                ]
                delegate: Item {
                    // Wrapping Item so MouseArea can use anchors.fill (a
                    // Column's children must not specify anchors, per Qt).
                    width: modeLabel.implicitWidth + 12
                    height: 28

                    readonly property bool isActive: (modelData.label === "PHOTO" && currentMode === "photo") || (modelData.label === "VIDEO" && currentMode === "video")

                    Column {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            id: modeLabel
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label
                            color: isActive ? MColors.marathonTealBright : MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1.2
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 16
                            height: 2
                            radius: 1
                            color: MColors.marathonTealBright
                            visible: isActive
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: {
                            HapticService.light();
                            currentMode = modelData.mode;
                        }
                    }
                }
            }
        }

        Row {
            id: bottomControls

            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: MSpacing.xl + MSpacing.lg
            spacing: MSpacing.xl * 2
            z: 10
            visible: cameraController.ready

            Item {
                width: 60
                height: 60
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    id: galleryThumbnailBorder

                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: "white"
                }

                Item {
                    id: thumbnailContent

                    anchors.fill: parent
                    anchors.margins: 3
                    visible: false

                    Image {
                        anchors.fill: parent
                        source: cameraController.latestPhotoPath
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(120, 120)
                        visible: cameraController.latestPhotoPath !== ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "#2a2a3a"
                        visible: cameraController.latestPhotoPath === ""

                        Icon {
                            anchors.centerIn: parent
                            name: "image"
                            size: 24
                            color: MColors.textSecondary
                        }
                    }
                }

                Rectangle {
                    id: thumbnailMask

                    anchors.fill: thumbnailContent
                    radius: width / 2
                    visible: false
                }

                OpacityMask {
                    anchors.fill: thumbnailContent
                    source: thumbnailContent
                    maskSource: thumbnailMask
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        NavigationService.launchApp("gallery");
                    }
                }
            }

            Rectangle {
                id: shutter
                width: 80
                height: 80
                radius: 40
                color: "transparent"
                border.width: 4
                border.color: cameraController.isRecording ? "#ff4444" : "white"

                // Teal-halo glow per JSX shutter — outer 3 px ring at low
                // alpha, only when not recording (red-record state owns the
                // visual emphasis instead).
                Rectangle {
                    visible: !cameraController.isRecording
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: parent.radius + 6
                    color: "transparent"
                    border.width: 3
                    border.color: MColors.tealHalo
                    opacity: 0.55
                    z: -1
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: cameraController.isRecording ? 28 : parent.width - 12
                    height: cameraController.isRecording ? 28 : parent.height - 12
                    radius: cameraController.isRecording ? 6 : width / 2
                    color: cameraController.isRecording ? "#ff4444" : "white"

                    Behavior on width {
                        NumberAnimation {
                            duration: MMotion.durationFor("hover")
                        }
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: MMotion.durationFor("hover")
                        }
                    }

                    Behavior on radius {
                        NumberAnimation {
                            duration: MMotion.durationFor("hover")
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        parent.scale = 0.9;
                        HapticService.medium();
                    }
                    onReleased: parent.scale = 1
                    onCanceled: parent.scale = 1
                    onClicked: {
                        if (currentMode === "photo") {
                            cameraController.captureWithTimer();
                        } else {
                            if (cameraController.isRecording)
                                cameraController.stopRecording();
                            else
                                cameraController.startRecording();
                        }
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: MMotion.micro
                    }
                }
            }

            MIconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "refresh-cw"
                iconSize: 24
                width: 56
                height: 56
                variant: "secondary"
                rotation: cameraController.isFrontCamera ? 180 : 0
                onClicked: cameraController.flipCamera()

                // Spring-driven flip rotation per the M3 Expressive
                // motion ladder — replaces OutBack overshoot with
                // tunable physics on the "nav" role.
                Behavior on rotation {
                    SpringAnimation {
                        spring: MMotion.stiffnessSpatialFor("nav")
                        damping: MMotion.dampingSpatialFor("nav")
                        epsilon: MMotion.epsilonSpatial
                    }
                }
            }
        }

        MSheet {
            id: settingsSheet

            title: "Camera Settings"
            sheetHeight: 0.5
            onClosed: settingsSheet.hide()

            content: Column {
                width: parent.width
                spacing: MSpacing.lg

                Column {
                    width: parent.width
                    spacing: MSpacing.sm

                    Text {
                        text: "Timer"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                    }

                    Row {
                        spacing: MSpacing.md

                        Repeater {

                            model: ListModel {
                                ListElement {
                                    label: "Off"
                                    value: 0
                                }

                                ListElement {
                                    label: "3s"
                                    value: 3
                                }

                                ListElement {
                                    label: "10s"
                                    value: 10
                                }
                            }

                            delegate: MButton {
                                required property string label
                                required property int value

                                text: label
                                variant: cameraController.timerDuration === value ? "primary" : "secondary"
                                onClicked: {
                                    cameraController.timerDuration = value;
                                    HapticService.light();
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: MSpacing.touchTargetMedium

                    Text {
                        text: "Camera"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: cameraController.currentCameraName || "None"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeSmall
                        elide: Text.ElideRight
                        width: parent.width * 0.6
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Item {
                    width: parent.width
                    height: MSpacing.touchTargetMedium

                    Text {
                        text: "Save Location"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Pictures/Marathon"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeSmall
                    }
                }
            }
        }
    }
}
