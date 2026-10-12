pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Nemo.Ngf 1.0
import MarathonApp.Camera 1.0
import "../components"

Page {
    id: page

    property var app
    readonly property QtObject camera: app.camera
    readonly property bool video: app.mode === "video"
    readonly property bool settingsOpen: settings.open
    readonly property bool controlsShown: camera.ready && !app.cameraFailed

    function openSettings() {
        settings.show();
    }

    function closeSettings() {
        settings.hide();
    }

    function shoot() {
        feedback.play();
        app.shoot();
    }

    allowedOrientations: Orientation.Portrait
    palette.colorScheme: Theme.LightOnDark
    backgroundColor: Theme.darkPrimaryColor
    Component.onCompleted: camera.videoSink = viewfinder.videoSink

    // Forwarded first, so Escape closes the settings before Page's own Escape goes back.
    Keys.forwardTo: [keys]

    Item {
        id: keys

        Keys.onPressed: function (event) {
            if (page.settingsOpen) {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    page.closeSettings();
                }
                return;
            }
            if (page.controlsShown && (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                event.accepted = true;
                page.shoot();
            }
        }
    }

    NonGraphicalFeedback {
        id: feedback
        event: "feedback_press"
    }

    Connections {
        target: page.camera
        function onPhotoSaved(path) {
            feedback.play();
            flashOverlay.opacity = 1;
            flashFade.restart();
        }
        function onCameraFlipStarted() {
            flipAnimation.restart();
        }
    }

    SoftwareVideoOutput {
        id: viewfinder

        objectName: "viewfinder"
        anchors.fill: parent
        fillMode: SoftwareVideoOutput.PreserveAspectFit
        visible: page.camera.active

        transform: Rotation {
            id: viewfinderRotation

            origin.x: viewfinder.width / 2
            origin.y: viewfinder.height / 2
            axis { x: 0; y: 1; z: 0 }
        }
    }

    SequentialAnimation {
        id: flipAnimation

        NumberAnimation {
            target: viewfinderRotation
            property: "angle"
            from: 0
            to: 90
            duration: 150
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: viewfinderRotation
            property: "angle"
            from: -90
            to: 0
            duration: 150
            easing.type: Easing.OutQuad
        }
    }

    // Taps focus, pinches zoom, a swipe down opens the settings.
    Item {
        objectName: "gestureArea"
        anchors.fill: parent
        enabled: page.camera.active

        TapHandler {
            onTapped: function (eventPoint) {
                const p = eventPoint.position;
                focusRing.x = p.x - focusRing.width / 2;
                focusRing.y = p.y - focusRing.height / 2;
                focusRingAnimation.restart();
                page.camera.focusOnPoint(p.x / page.width, p.y / page.height);
            }
        }

        PinchHandler {
            target: null
            onScaleChanged: function (delta) {
                page.camera.zoomLevel = page.camera.zoomLevel * delta;
            }
        }

        DragHandler {
            target: null
            xAxis.enabled: false
            maximumPointCount: 1
            onTranslationChanged: {
                if (active && translation.y > Theme.itemSizeMedium && !page.settingsOpen)
                    page.openSettings();
            }
        }
    }

    Item {
        id: grid

        anchors.fill: parent
        visible: page.camera.active

        Repeater {
            model: 2

            Rectangle {
                required property int index

                x: grid.width * (index + 1) / 3
                width: Math.max(1, Math.round(Theme.pixelRatio))
                height: grid.height
                color: Theme.rgba(Theme.lightPrimaryColor, Theme.opacityFaint)
            }
        }

        Repeater {
            model: 2

            Rectangle {
                required property int index

                y: grid.height * (index + 1) / 3
                width: grid.width
                height: Math.max(1, Math.round(Theme.pixelRatio))
                color: Theme.rgba(Theme.lightPrimaryColor, Theme.opacityFaint)
            }
        }
    }

    Rectangle {
        id: focusRing

        width: Theme.itemSizeLarge
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, Math.round(Theme.pixelRatio * 2))
        border.color: Theme.highlightColor
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
                    duration: 250
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: focusRing
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: 250
                }
            }
            PauseAnimation {
                duration: 500
            }
            NumberAnimation {
                target: focusRing
                property: "opacity"
                to: 0
                duration: 400
            }
        }
    }

    Label {
        objectName: "countdown"
        anchors.centerIn: parent
        visible: page.camera.timerActive && page.camera.timerCountdown > 0
        text: page.camera.timerCountdown
        color: Theme.lightPrimaryColor
        font.pixelSize: 3 * Theme.fontSizeHuge
        style: Text.Outline
        styleColor: Theme.darkPrimaryColor
    }

    Row {
        id: status

        objectName: "status"
        anchors {
            top: parent.top
            left: parent.left
            topMargin: Theme.paddingLarge
            leftMargin: Theme.horizontalPageMargin
        }
        height: settingsButton.height
        spacing: Theme.paddingMedium
        visible: page.controlsShown && !page.camera.isRecording && !settings.expanded

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: page.camera.flashAvailable
            source: page.camera.flashEnabled ? "image://theme/icon-m-flash" : "image://theme/icon-m-flash-off"
            color: Theme.lightPrimaryColor
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: page.camera.timerDuration > 0
            spacing: Theme.paddingSmall

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-m-timer"
                color: Theme.lightPrimaryColor
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("%1 s").arg(page.camera.timerDuration)
                color: Theme.lightPrimaryColor
            }
        }
    }

    IconButton {
        id: settingsButton

        objectName: "settingsButton"
        anchors {
            top: parent.top
            right: parent.right
            topMargin: Theme.paddingLarge
            rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
        }
        visible: page.controlsShown && !page.camera.isRecording && !settings.expanded
        icon.source: "image://theme/icon-m-settings"
        icon.color: Theme.lightPrimaryColor
        Accessible.name: qsTr("Camera settings")
        onClicked: page.openSettings()
    }

    Rectangle {
        objectName: "recordingIndicator"
        anchors {
            top: parent.top
            topMargin: Theme.paddingLarge
            horizontalCenter: parent.horizontalCenter
        }
        visible: page.camera.isRecording
        width: recordingRow.width + 2 * Theme.paddingLarge
        height: Theme.itemSizeExtraSmall
        radius: height / 2
        color: Theme.rgba(Theme.darkPrimaryColor, Theme.opacityHigh)

        Row {
            id: recordingRow

            anchors.centerIn: parent
            spacing: Theme.paddingMedium

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.paddingLarge
                height: width
                radius: width / 2
                color: Theme.errorColor

                SequentialAnimation on opacity {
                    running: page.camera.isRecording
                    loops: Animation.Infinite

                    NumberAnimation { from: 1; to: 0.2; duration: 500 }
                    NumberAnimation { from: 0.2; to: 1; duration: 500 }
                }
            }

            Label {
                objectName: "recordingTime"
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const d = page.camera.recordingDuration;
                    const secs = d % 60;
                    return Math.floor(d / 60) + ":" + (secs < 10 ? "0" : "") + secs;
                }
                color: Theme.lightPrimaryColor
                font.pixelSize: Theme.fontSizeLarge
            }
        }
    }

    Rectangle {
        objectName: "zoomIndicator"
        anchors {
            bottom: modeSwitch.top
            bottomMargin: Theme.paddingLarge
            horizontalCenter: parent.horizontalCenter
        }
        visible: page.camera.active && page.camera.zoomLevel > 1
        width: zoomLabel.width + 2 * Theme.paddingMedium
        height: zoomLabel.height + Theme.paddingSmall
        radius: height / 2
        color: Theme.rgba(Theme.darkPrimaryColor, Theme.opacityLow)

        Label {
            id: zoomLabel

            anchors.centerIn: parent
            text: qsTr("%1×").arg(page.camera.zoomLevel.toFixed(1))
            color: Theme.lightPrimaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    ModeSwitch {
        id: modeSwitch

        objectName: "modeSwitch"
        anchors {
            bottom: shutter.top
            bottomMargin: Theme.paddingLarge
            horizontalCenter: parent.horizontalCenter
        }
        visible: page.controlsShown
        enabled: !page.camera.isRecording
        opacity: enabled ? 1 : Theme.opacityLow
        mode: page.app.mode
        onSelected: function (mode) {
            page.app.setMode(mode);
        }
    }

    CaptureThumbnail {
        objectName: "thumbnail"
        anchors {
            left: parent.left
            leftMargin: Theme.horizontalPageMargin
            verticalCenter: shutter.verticalCenter
        }
        visible: page.controlsShown
        source: page.camera.latestPhotoPath
        onClicked: page.app.openGallery()
    }

    ShutterButton {
        id: shutter

        objectName: "shutter"
        anchors {
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge * 2
            horizontalCenter: parent.horizontalCenter
        }
        visible: page.controlsShown
        enabled: page.camera.active
        video: page.video
        recording: page.camera.isRecording
        onClicked: page.shoot()
    }

    IconButton {
        objectName: "flipButton"
        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: shutter.verticalCenter
        }
        visible: page.controlsShown
        enabled: page.camera.cameraCount > 1 && !page.camera.isRecording
        icon.source: "image://theme/icon-m-camera-switch"
        icon.color: Theme.lightPrimaryColor
        Accessible.name: qsTr("Switch camera")
        rotation: page.camera.isFrontCamera ? 180 : 0
        onClicked: page.camera.flipCamera()

        Behavior on rotation {
            NumberAnimation { duration: 300; easing.type: Easing.InOutQuad }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.darkPrimaryColor
        visible: page.camera.ready && !page.camera.active && !page.app.cameraFailed

        BusyLabel {
            objectName: "startingLabel"
            running: parent.visible
            text: qsTr("Starting camera…")
        }
    }

    SilicaFlickable {
        objectName: "problem"
        anchors.fill: parent
        visible: page.camera.cameraCount === 0 || (page.app.cameraFailed && !page.camera.active)
        contentHeight: height

        PullDownMenu {
            MenuItem {
                objectName: "problemAction"
                text: page.camera.cameraCount === 0 ? qsTr("Grant camera access") : qsTr("Try again")
                onClicked: {
                    if (page.camera.cameraCount === 0)
                        Permissions.requestPermission(page.app.appId, "camera");
                    else
                        page.app.retry();
                }
            }
        }

        ViewPlaceholder {
            objectName: "placeholder"
            enabled: true
            text: page.camera.cameraCount === 0 ? qsTr("Camera unavailable") : qsTr("Camera stopped working")
            hintText: page.camera.cameraCount === 0
                      ? qsTr("No working camera found. If this device has one, pull down to give Camera access to it.")
                      : qsTr("Another app may be using the camera. Pull down to try again.")
        }
    }

    Rectangle {
        id: flashOverlay

        anchors.fill: parent
        color: Theme.lightPrimaryColor
        opacity: 0
        visible: opacity > 0

        NumberAnimation on opacity {
            id: flashFade

            running: false
            to: 0
            duration: 200
        }
    }

    SettingsPanel {
        id: settings

        objectName: "settingsPanel"
        camera: page.camera
    }
}
