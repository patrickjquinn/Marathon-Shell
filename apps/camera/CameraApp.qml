import MarathonApp.Camera 1.0
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

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

        Column {
            anchors.centerIn: parent
            spacing: MSpacing.lg
            visible: cameraController.cameraCount === 0

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

        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: MSpacing.xl
            anchors.rightMargin: MSpacing.xl
            spacing: MSpacing.xl
            z: 10
            visible: cameraController.ready

            MIconButton {
                iconName: cameraController.flashEnabled ? "zap" : "zap-off"
                iconSize: 22
                width: 48
                height: 48
                variant: cameraController.flashEnabled ? "primary" : "secondary"
                visible: cameraController.flashAvailable
                onClicked: {
                    HapticService.light();
                    cameraController.flashEnabled = !cameraController.flashEnabled;
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
            visible: cameraController.ready

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
                width: 80
                height: 80
                radius: 40
                color: "transparent"
                border.width: 4
                border.color: cameraController.isRecording ? "#ff4444" : "white"

                Rectangle {
                    anchors.centerIn: parent
                    width: cameraController.isRecording ? 28 : parent.width - 12
                    height: cameraController.isRecording ? 28 : parent.height - 12
                    radius: cameraController.isRecording ? 6 : width / 2
                    color: cameraController.isRecording ? "#ff4444" : "white"

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
                rotation: cameraController.isFrontCamera ? 180 : 0
                onClicked: cameraController.flipCamera()

                Behavior on rotation {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.OutBack
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
