import QtQuick
import QtMultimedia
import Qt.labs.platform
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Modals

MApp {
    id: cameraApp
    appId: "camera"
    appName: "Camera"
    appIcon: "assets/icon.svg"

    property string currentMode: "photo"
    property bool flashEnabled: false
    property int photoCount: 0
    property bool isRecording: false
    property bool frontCamera: false
    property string savePath: StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/Marathon"
    property int recordingSeconds: 0
    property bool hasPermission: false

    Timer {
        id: recordingTimer
        interval: 1000
        running: isRecording
        repeat: true
        onTriggered: {
            recordingSeconds++;
        }
    }

    function updateLatestPhoto() {
        if (typeof MediaLibraryManager !== 'undefined') {
            var photos = MediaLibraryManager.getAllPhotos();
            if (photos && photos.length > 0) {
                // Photos are sorted by timestamp DESC
                var photo = photos[0];
                latestPhotoPath = photo.thumbnailPath || photo.path;
                Logger.info("Camera", "Latest photo: " + latestPhotoPath);
            } else {
                latestPhotoPath = "";
            }
        }
    }

    // Listen for new media
    Connections {
        target: typeof MediaLibraryManager !== 'undefined' ? MediaLibraryManager : null
        function onLibraryChanged() {
            updateLatestPhoto();
        }
        function onNewMediaAdded(path) {
            updateLatestPhoto();
        }
    }

    property string latestPhotoPath: ""

    Component.onCompleted: {
        var dir = Qt.createQmlObject('import Qt.labs.platform; FolderDialog {}', cameraApp);
        var folder = new String(savePath);
        Logger.info("Camera", "Save path: " + savePath);

        // Check camera permission
        if (typeof PermissionManager !== 'undefined') {
            if (PermissionManager.hasPermission(appId, "camera")) {
                Logger.info("Camera", "Camera permission already granted");
                hasPermission = true;
                initializeCamera();
            } else {
                Logger.info("Camera", "Requesting camera permission");
                PermissionManager.requestPermission(appId, "camera");
            }
        } else {
            Logger.warn("Camera", "PermissionManager not available, auto-granting");
            hasPermission = true;
            initializeCamera();
        }

        // Load latest photo
        updateLatestPhoto();
    }

    function initializeCamera() {
        Logger.info("Camera", "Initializing camera hardware");
        camera.active = true;
    }

    // Listen for permission responses
    Connections {
        target: typeof PermissionManager !== 'undefined' ? PermissionManager : null

        function onPermissionGranted(grantedAppId, permission) {
            if (grantedAppId === appId && permission === "camera") {
                Logger.info("Camera", "Camera permission granted");
                hasPermission = true;
                initializeCamera();
            }
        }

        function onPermissionDenied(deniedAppId, permission) {
            if (deniedAppId === appId && permission === "camera") {
                Logger.warn("Camera", "Camera permission denied");
                hasPermission = false;
            }
        }
    }

    // List available cameras
    MediaDevices {
        id: mediaDevices
    }

    // Media capture session (Qt6 way) - defined after content to avoid forward reference
    property var captureSession: null

    // Camera component
    Camera {
        id: camera
        active: false  // Will be activated after permission is granted

        Component.onCompleted: {
            // Set initial camera device
            if (mediaDevices.videoInputs.length > 0) {
                cameraDevice = mediaDevices.videoInputs[0];
            }
        }

        // Error handling
        onErrorOccurred: function (error, errorString) {
            Logger.error("Camera", "Camera error: " + errorString);
        }
    }

    // Image capture component
    ImageCapture {
        id: imageCapture

        onImageSaved: function (id, path) {
            photoCount++;
            Logger.info("Camera", "Photo saved: " + path);
            if (typeof MediaLibraryManager !== 'undefined') {
                MediaLibraryManager.scanLibrary();
            }
            // Update thumbnail immediately if possible, though scanLibrary will trigger signal
            latestPhotoPath = "file://" + path;
        }

        onErrorOccurred: function (id, error, errorString) {
            Logger.error("Camera", "Image capture error: " + errorString);
        }
    }

    // Video recording component
    MediaRecorder {
        id: mediaRecorder

        onRecorderStateChanged: function (state) {
            if (state === MediaRecorder.RecordingState) {
                isRecording = true;
            } else if (state === MediaRecorder.StoppedState) {
                isRecording = false;
            }
        }

        onErrorOccurred: function (error, errorString) {
            Logger.error("Camera", "Video recording error: " + errorString);
            isRecording = false;
        }
    }

    // Flash overlay
    Rectangle {
        id: flashOverlay
        anchors.fill: parent
        color: "white"
        opacity: 0.0
        visible: opacity > 0
        z: 100

        Behavior on opacity {
            NumberAnimation {
                duration: 100
            }
        }
    }

    function triggerFlash() {
        flashOverlay.opacity = 1.0;
        flashTimer.restart();
    }

    Timer {
        id: flashTimer
        interval: 50
        onTriggered: flashOverlay.opacity = 0.0
    }

    content: Rectangle {
        anchors.fill: parent
        color: "black" // Use black background for camera

        // Permission denied placeholder
        Column {
            anchors.centerIn: parent
            spacing: MSpacing.lg
            visible: !hasPermission

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "📷"
                font.pixelSize: 64
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Camera Permission Required"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Bold
                color: MColors.textPrimary
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Please grant camera permission to use this app"
                font.pixelSize: MTypography.sizeBody
                color: MColors.textSecondary
                horizontalAlignment: Text.AlignHCenter
                width: parent.parent.width * 0.8
                wrapMode: Text.WordWrap
            }

            MButton {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Request Permission"
                variant: "primary"
                onClicked: {
                    if (typeof PermissionManager !== 'undefined') {
                        PermissionManager.requestPermission(appId, "camera");
                    }
                }
            }
        }

        // Full-screen camera viewfinder
        VideoOutput {
            id: viewfinder
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
            visible: hasPermission

            // Tap to focus
            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    var point = Qt.point(mouse.x / width, mouse.y / height);
                    camera.focusPoint = point;
                    camera.focusMode = Camera.FocusModeAutoNear;

                    // Visual feedback
                    focusRing.x = mouse.x - focusRing.width / 2;
                    focusRing.y = mouse.y - focusRing.height / 2;
                    focusRing.visible = true;
                    focusRingAnimation.restart();
                }
            }

            Rectangle {
                id: focusRing
                width: 64
                height: 64
                radius: 32
                color: "transparent"
                border.width: 2
                border.color: MColors.accent
                visible: false

                SequentialAnimation {
                    id: focusRingAnimation
                    NumberAnimation {
                        target: focusRing
                        property: "scale"
                        from: 1.5
                        to: 1.0
                        duration: 200
                        easing.type: Easing.OutQuad
                    }
                    PauseAnimation {
                        duration: 500
                    }
                    NumberAnimation {
                        target: focusRing
                        property: "opacity"
                        from: 1.0
                        to: 0.0
                        duration: 200
                    }
                    ScriptAction {
                        script: {
                            focusRing.visible = false;
                            focusRing.opacity = 1.0;
                        }
                    }
                }
            }
        }

        // Recording time indicator
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: MSpacing.lg + 40 // Move down to avoid status bar overlap
            width: Constants.touchTargetLarge * 2
            height: Constants.touchTargetMedium
            radius: Constants.borderRadiusSharp
            color: "#80000000"
            visible: isRecording

            Row {
                anchors.centerIn: parent
                spacing: MSpacing.sm

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: MSpacing.md
                    height: MSpacing.md
                    radius: width / 2
                    color: MColors.error

                    SequentialAnimation on opacity {
                        running: isRecording
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: 1.0
                            to: 0.0
                            duration: 500
                        }
                        NumberAnimation {
                            from: 0.0
                            to: 1.0
                            duration: 500
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.floor(recordingSeconds / 60) + ":" + (recordingSeconds % 60 < 10 ? "0" : "") + (recordingSeconds % 60)
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.Bold
                    color: "white"
                }
            }
        }

        // Setup capture session after viewfinder is created
        Component.onCompleted: {
            captureSession = Qt.createQmlObject(`
                import QtMultimedia
                CaptureSession {
                    camera: camera
                    imageCapture: imageCapture
                    recorder: mediaRecorder
                    videoOutput: viewfinder
                }
            `, cameraApp);
        }

        // Dark overlay for better UI contrast (gradient at top/bottom)
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: "#80000000"
                }
                GradientStop {
                    position: 0.2
                    color: "transparent"
                }
                GradientStop {
                    position: 0.8
                    color: "transparent"
                }
                GradientStop {
                    position: 1.0
                    color: "#80000000"
                }
            }
        }

        // Top right controls
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: MSpacing.xl
            anchors.rightMargin: MSpacing.xl
            spacing: MSpacing.xl // Increased spacing
            z: 10

            MIconButton {
                iconName: flashEnabled ? "zap" : "zap-off"
                iconSize: 20
                width: 48 // Larger touch target
                height: 48
                variant: flashEnabled ? "primary" : "secondary"
                onClicked: {
                    HapticService.light();
                    flashEnabled = !flashEnabled;
                    if (camera.cameraDevice && camera.cameraDevice.flashMode !== undefined) {
                        camera.flashMode = flashEnabled ? Camera.FlashOn : Camera.FlashOff;
                    }
                }
            }

            MIconButton {
                iconName: "settings"
                iconSize: 20
                width: 48 // Larger touch target
                height: 48
                variant: "secondary"
                onClicked: {
                    HapticService.light();
                    settingsSheet.show();
                }
            }
        }

        // Mode Switcher (Moved to bottom)
        Row {
            anchors.bottom: bottomControls.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: MSpacing.xl
            spacing: MSpacing.xl
            z: 10

            MButton {
                text: "PHOTO"
                variant: currentMode === "photo" ? "primary" : "text"
                opacity: currentMode === "photo" ? 1.0 : 0.6
                onClicked: {
                    HapticService.light();
                    currentMode = "photo";
                }
            }

            MButton {
                text: "VIDEO"
                variant: currentMode === "video" ? "primary" : "text"
                opacity: currentMode === "video" ? 1.0 : 0.6
                onClicked: {
                    HapticService.light();
                    currentMode = "video";
                }
            }
        }

        // Bottom controls
        Row {
            id: bottomControls
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: MSpacing.xl + MSpacing.lg
            spacing: MSpacing.xl * 2 // More spacing between shutter and other buttons
            z: 10

            // Gallery button with thumbnail
            Rectangle {
                id: galleryButton
                width: 56
                height: 56
                radius: 28
                color: "transparent"
                anchors.verticalCenter: parent.verticalCenter
                clip: true

                // Thumbnail image
                Image {
                    anchors.fill: parent
                    source: latestPhotoPath
                    visible: latestPhotoPath !== ""
                    fillMode: Image.PreserveAspectCrop
                }

                // Border
                Rectangle {
                    anchors.fill: parent
                    radius: 28
                    color: "transparent"
                    border.width: 2
                    border.color: "white"
                    visible: latestPhotoPath !== ""
                }

                // Default icon if no photo
                MIconButton {
                    anchors.centerIn: parent
                    iconName: "image"
                    iconSize: 24
                    width: 56
                    height: 56
                    variant: "secondary"
                    visible: latestPhotoPath === ""
                    onClicked: galleryButton.openGallery()
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: latestPhotoPath !== ""
                    onClicked: galleryButton.openGallery()
                }

                function openGallery() {
                    HapticService.light();
                    if (latestPhotoPath) {
                        Logger.info("Camera", "Opening photo: " + latestPhotoPath);
                        Qt.openUrlExternally(latestPhotoPath);
                    } else {
                        Logger.info("Camera", "No photos to open");
                    }
                }
            }

            // Main capture button
            Rectangle {
                width: 80
                height: 80
                radius: 40
                color: "transparent"
                border.width: 4
                border.color: isRecording ? MColors.error : "white"
                antialiasing: true

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 12
                    height: parent.height - 12
                    radius: width / 2
                    color: isRecording ? MColors.error : "white"
                    antialiasing: true

                    Behavior on width {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                    Behavior on height {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                    Behavior on radius {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                }

                // Recording indicator (square shape when recording)
                Rectangle {
                    anchors.centerIn: parent
                    width: isRecording ? 24 : 0
                    height: isRecording ? 24 : 0
                    radius: 4
                    color: "white"
                    visible: isRecording
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        parent.scale = 0.9;
                        HapticService.medium();
                    }
                    onReleased: {
                        parent.scale = 1.0;
                    }
                    onCanceled: {
                        parent.scale = 1.0;
                    }
                    onClicked: {
                        if (currentMode === "photo") {
                            triggerFlash();
                            imageCapture.capture();
                            Logger.info("Camera", "Photo taken");
                        } else {
                            if (isRecording) {
                                mediaRecorder.stop();
                                isRecording = false;
                                recordingSeconds = 0;
                                Logger.info("Camera", "Video recording stopped");
                            } else {
                                mediaRecorder.outputLocation = "file://" + savePath + "/VID_" + Date.now() + ".mp4";
                                mediaRecorder.record();
                                isRecording = true;
                                recordingSeconds = 0;
                                Logger.info("Camera", "Video recording started");
                            }
                        }
                    }
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: 100
                    }
                }
            }

            // Camera switch button
            MIconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "refresh-cw"
                iconSize: 24
                width: 56
                height: 56
                variant: "secondary"
                onClicked: {
                    HapticService.light();
                    frontCamera = !frontCamera;

                    // Switch camera device
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
                        Logger.info("Camera", "Switched to camera: " + camera.cameraDevice.description);
                    }
                }
            }
        }

        // Settings Sheet
        MSheet {
            id: settingsSheet
            title: "Camera Settings"
            sheetHeight: 0.4
            onClosed: settingsSheet.hide()

            content: Column {
                width: parent.width
                spacing: MSpacing.lg

                // Grid Toggle
                Item {
                    width: parent.width
                    height: MSpacing.touchTargetMedium

                    Text {
                        text: "Grid Lines"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }

                    MButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Off" // Placeholder
                        variant: "secondary"
                        onClicked:
                        // TODO: Implement grid
                        {}
                    }
                }

                // Timer
                Item {
                    width: parent.width
                    height: MSpacing.touchTargetMedium

                    Text {
                        text: "Timer"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }

                    MButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Off"
                        variant: "secondary"
                    }
                }

                // Storage
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
