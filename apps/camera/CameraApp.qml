import MarathonApp.Camera 1.0
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import Qt.labs.folderlistmodel
import Qt.labs.platform
import QtMultimedia
import QtQuick
import QtQuick.Controls

MApp {
    id: cameraApp

    property string currentMode: "photo"
    property bool flashEnabled: false
    property int photoCount: 0
    property bool isRecording: false
    property bool frontCamera: false
    property string savePath: StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/Marathon"
    property bool cameraActive: false
    property bool cameraReady: false
    property string cameraErrorMessage: ""
    property string latestPhotoPath: galleryModel.count > 0 ? galleryModel.get(0, "fileUrl") : ""
    property int recordingDuration: 0
    property bool previewAvailable: false
    property real zoomLevel: 1
    property real minZoom: 1
    property real maxZoom: 8
    property point focusPoint: Qt.point(0.5, 0.5)
    property bool focusAnimating: false
    property int timerDuration: 0
    property int timerCountdown: 0
    property bool timerActive: false
    property var availableResolutions: []
    property int selectedResolutionIndex: 0

    function triggerFlash() {
        flashOverlay.opacity = 1;
        flashTimer.restart();
    }

    function captureWithTimer() {
        if (timerDuration > 0) {
            timerCountdown = timerDuration;
            timerActive = true;
            countdownTimer.start();
        } else {
            doCapture();
        }
    }

    function doCapture() {
        if (currentMode === "photo") {
            imageCapture.captureToFile(savePath + "/IMG_" + Date.now() + ".jpg");
            HapticService.heavy();
        } else {
            if (isRecording) {
                mediaRecorder.stop();
            } else {
                var videoPath = savePath + "/VID_" + Date.now() + ".mp4";
                mediaRecorder.outputLocation = "file://" + videoPath;
                mediaRecorder.record();
            }
        }
    }

    function setZoom(level) {
        zoomLevel = Math.max(minZoom, Math.min(maxZoom, level));
        if (camera.focusController) {}
    }

    appId: "camera"
    appName: "Camera"
    appIcon: "assets/icon.svg"
    Component.onCompleted: {
        console.warn("[Camera] Starting camera app");
    }

    FolderListModel {
        id: galleryModel

        folder: "file://" + savePath
        nameFilters: ["*.jpg", "*.jpeg", "*.png"]
        sortField: FolderListModel.Time
        sortReversed: true
        showDirs: false
    }

    Timer {
        id: recordingTimer

        interval: 1000
        running: isRecording
        repeat: true
        onTriggered: recordingDuration++
    }

    Timer {
        id: countdownTimer

        interval: 1000
        running: timerActive
        repeat: true
        onTriggered: {
            timerCountdown--;
            HapticService.light();
            if (timerCountdown <= 0) {
                timerActive = false;
                stop();
                doCapture();
            }
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
                duration: 50
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
        color: "#1a1a2e"

        MediaDevices {
            id: mediaDevices

            Component.onCompleted: {
                console.warn("[Camera] Found " + videoInputs.length + " cameras");
                if (videoInputs.length > 0)
                    cameraReady = true;
            }
        }

        Camera {
            id: camera

            active: cameraReady
            Component.onCompleted: {
                if (mediaDevices.videoInputs.length > 0) {
                    cameraDevice = mediaDevices.videoInputs[0];
                    console.warn("[Camera] Using camera: " + cameraDevice.description);
                }
            }
            onActiveChanged: {
                console.warn("[Camera] Camera active: " + active);
                cameraActive = active;
            }
            onErrorOccurred: (error, errorString) => {
                console.warn("[Camera] Error: " + errorString);
                cameraErrorMessage = errorString;
            }
        }

        ImageCapture {
            id: imageCapture

            onImageSaved: (id, path) => {
                photoCount++;
                console.warn("[Camera] Photo saved: " + path);
                latestPhotoPath = "file://" + path;
                triggerFlash();
                HapticService.medium();
                if (typeof MediaLibraryManager !== 'undefined')
                    MediaLibraryManager.scanLibrary();
            }
            onErrorOccurred: (id, error, errorString) => {
                console.warn("[Camera] Capture error: " + errorString);
            }
        }

        MediaRecorder {
            id: mediaRecorder

            onRecorderStateChanged: {
                isRecording = (recorderState === MediaRecorder.RecordingState);
                if (recorderState === MediaRecorder.StoppedState)
                    recordingDuration = 0;
            }
            onErrorOccurred: (error, errorString) => {
                console.warn("[Camera] Recording error: " + errorString);
                isRecording = false;
            }
        }

        CaptureSession {
            id: captureSession

            camera: camera
            imageCapture: imageCapture
            recorder: mediaRecorder
            videoOutput: viewfinder.videoSink
        }

        SoftwareVideoOutput {
            id: viewfinder

            anchors.fill: parent
            fillMode: SoftwareVideoOutput.PreserveAspectFit
            visible: cameraActive

            PinchHandler {
                target: null
                onActiveChanged: {
                    if (!active)
                        return;
                }
                onScaleChanged: delta => {
                    var newZoom = zoomLevel * delta;
                    setZoom(newZoom);
                }
            }

            TapHandler {
                onTapped: eventPoint => {
                    var point = eventPoint.position;
                    focusRing.x = point.x - focusRing.width / 2;
                    focusRing.y = point.y - focusRing.height / 2;
                    focusRingAnimation.restart();
                    focusPoint = Qt.point(point.x / width, point.y / height);
                    if (camera.focusController && camera.focusMode === Camera.FocusModeAutoNear)
                        camera.customFocusPoint = focusPoint;
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
                            duration: 200
                            easing.type: Easing.OutCubic
                        }

                        NumberAnimation {
                            target: focusRing
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 200
                        }
                    }

                    PauseAnimation {
                        duration: 500
                    }

                    NumberAnimation {
                        target: focusRing
                        property: "opacity"
                        to: 0
                        duration: 300
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
                visible: zoomLevel > 1

                Text {
                    anchors.centerIn: parent
                    text: zoomLevel.toFixed(1) + "x"
                    color: "white"
                    font.weight: Font.Bold
                    font.pixelSize: 14
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
            text: timerCountdown
            visible: timerActive && timerCountdown > 0
        }

        Rectangle {
            id: viewfinderPlaceholder

            anchors.fill: parent
            color: "#0f0f23"
            visible: !cameraActive && cameraReady

            Item {
                anchors.fill: parent
                opacity: 0.3

                Rectangle {
                    x: parent.width / 3
                    width: 1
                    height: parent.height
                    color: "white"
                }

                Rectangle {
                    x: parent.width * 2 / 3
                    width: 1
                    height: parent.height
                    color: "white"
                }

                Rectangle {
                    y: parent.height / 3
                    width: parent.width
                    height: 1
                    color: "white"
                }

                Rectangle {
                    y: parent.height * 2 / 3
                    width: parent.width
                    height: 1
                    color: "white"
                }
            }

            Item {
                anchors.centerIn: parent
                width: 60
                height: 60

                Rectangle {
                    anchors.centerIn: parent
                    width: 2
                    height: 40
                    color: "#80ffffff"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 40
                    height: 2
                    color: "#80ffffff"
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 60
                    height: 60
                    radius: 30
                    color: "transparent"
                    border.width: 1
                    border.color: "#40ffffff"
                }
            }

            Column {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: 60
                spacing: 8

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: camera.cameraDevice ? camera.cameraDevice.description : "Camera"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: "#80ffffff"
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: cameraActive ? "● Ready" : "○ Initializing..."
                    font.pixelSize: 12
                    color: cameraActive ? "#4ade80" : "#fbbf24"
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    focusIndicator.x = mouse.x - 30;
                    focusIndicator.y = mouse.y - 30;
                    focusIndicator.visible = true;
                    focusAnimation.restart();
                    HapticService.light();
                    var point = Qt.point(mouse.x / width, mouse.y / height);
                    camera.focusPoint = point;
                    camera.focusMode = Camera.FocusModeAutoNear;
                }
            }

            Rectangle {
                id: focusIndicator

                width: 60
                height: 60
                radius: 30
                color: "transparent"
                border.width: 2
                border.color: MColors.accent
                visible: false

                SequentialAnimation {
                    id: focusAnimation

                    NumberAnimation {
                        target: focusIndicator
                        property: "scale"
                        from: 1.5
                        to: 1
                        duration: 200
                        easing.type: Easing.OutQuad
                    }

                    PauseAnimation {
                        duration: 800
                    }

                    NumberAnimation {
                        target: focusIndicator
                        property: "opacity"
                        to: 0
                        duration: 200
                    }

                    ScriptAction {
                        script: {
                            focusIndicator.visible = false;
                            focusIndicator.opacity = 1;
                        }
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: MSpacing.lg
            visible: mediaDevices.videoInputs.length === 0

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📷"
                font.pixelSize: 64
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No Camera Found"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Bold
                color: MColors.textPrimary
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: cameraReady

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
            visible: isRecording
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
                        running: isRecording
                        loops: Animation.Infinite

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
                        var mins = Math.floor(recordingDuration / 60);
                        var secs = recordingDuration % 60;
                        return mins + ":" + (secs < 10 ? "0" : "") + secs;
                    }
                    font.pixelSize: 18
                    font.bold: true
                    color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: MSpacing.xl
            anchors.rightMargin: MSpacing.xl
            spacing: MSpacing.xl
            z: 10
            visible: cameraReady

            MIconButton {
                iconName: flashEnabled ? "zap" : "zap-off"
                iconSize: 22
                width: 48
                height: 48
                variant: flashEnabled ? "primary" : "secondary"
                onClicked: {
                    HapticService.light();
                    flashEnabled = !flashEnabled;
                    camera.flashMode = flashEnabled ? Camera.FlashOn : Camera.FlashOff;
                }
            }

            MIconButton {
                iconName: "settings"
                iconSize: 22
                width: 48
                height: 48
                variant: "secondary"
                onClicked: {
                    HapticService.light();
                    settingsSheet.show();
                }
            }
        }

        Row {
            anchors.bottom: bottomControls.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: MSpacing.xl
            spacing: MSpacing.xl
            z: 10
            visible: cameraReady

            MButton {
                text: "PHOTO"
                variant: currentMode === "photo" ? "primary" : "text"
                opacity: currentMode === "photo" ? 1 : 0.6
                onClicked: {
                    HapticService.light();
                    currentMode = "photo";
                }
            }

            MButton {
                text: "VIDEO"
                variant: currentMode === "video" ? "primary" : "text"
                opacity: currentMode === "video" ? 1 : 0.6
                onClicked: {
                    HapticService.light();
                    currentMode = "video";
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
            visible: cameraReady

            Item {
                width: 60
                height: 60
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    id: galleryButton

                    anchors.fill: parent
                    radius: 30
                    color: latestPhotoPath !== "" ? "black" : "#2a2a3a"
                    border.width: 2
                    border.color: "white"
                    clip: true

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: latestPhotoPath
                        visible: latestPhotoPath !== ""
                        fillMode: Image.PreserveAspectCrop
                    }

                    Icon {
                        anchors.centerIn: parent
                        name: "image"
                        size: 24
                        color: MColors.textSecondary
                        visible: latestPhotoPath === ""
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 30
                    color: "transparent"
                    border.width: 2
                    border.color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light();
                        if (latestPhotoPath)
                            Qt.openUrlExternally(latestPhotoPath);
                    }
                }
            }

            Rectangle {
                width: 80
                height: 80
                radius: 40
                color: "transparent"
                border.width: 4
                border.color: isRecording ? "#ff4444" : "white"

                Rectangle {
                    anchors.centerIn: parent
                    width: isRecording ? 28 : parent.width - 12
                    height: isRecording ? 28 : parent.height - 12
                    radius: isRecording ? 6 : width / 2
                    color: isRecording ? "#ff4444" : "white"

                    Behavior on width {
                        NumberAnimation {
                            duration: 150
                        }
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 150
                        }
                    }

                    Behavior on radius {
                        NumberAnimation {
                            duration: 150
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
                        console.warn("[Camera] Shutter pressed");
                        captureWithTimer();
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 100
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
                visible: mediaDevices.videoInputs.length >= 1
                onClicked: {
                    HapticService.light();
                    frontCamera = !frontCamera;
                    if (mediaDevices.videoInputs.length > 1) {
                        var currentIndex = -1;
                        for (var i = 0; i < mediaDevices.videoInputs.length; i++) {
                            if (mediaDevices.videoInputs[i].id === camera.cameraDevice.id) {
                                currentIndex = i;
                                break;
                            }
                        }
                        var nextIndex = (currentIndex + 1) % mediaDevices.videoInputs.length;
                        camera.cameraDevice = mediaDevices.videoInputs[nextIndex];
                        console.warn("[Camera] Switched to: " + camera.cameraDevice.description);
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

                            delegate: Item {
                                width: (parent.parent.width - (MSpacing.md * 2)) / 3
                                height: MSpacing.touchTargetMin

                                MButton {
                                    anchors.fill: parent
                                    text: model.label
                                    variant: timerDuration === model.value ? "primary" : "secondary"
                                    onClicked: {
                                        timerDuration = model.value;
                                        HapticService.light();
                                    }
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
                        text: camera.cameraDevice ? camera.cameraDevice.description : "None"
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
