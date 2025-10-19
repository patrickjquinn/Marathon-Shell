import QtQuick
import QtQuick.Controls
import QtMultimedia
import Qt.labs.platform
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

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
    
    Timer {
        id: recordingTimer
        interval: 1000
        running: isRecording
        repeat: true
        onTriggered: {
            recordingSeconds++
        }
    }
    
    Component.onCompleted: {
        var dir = Qt.createQmlObject('import Qt.labs.platform; FolderDialog {}', cameraApp)
        var folder = new String(savePath)
        Logger.info("Camera", "Save path: " + savePath)
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
        active: true
        
        Component.onCompleted: {
            // Set initial camera device
            if (mediaDevices.videoInputs.length > 0) {
                cameraDevice = mediaDevices.videoInputs[0]
            }
        }
        
        // Error handling
        onErrorOccurred: function(error, errorString) {
            Logger.error("Camera", "Camera error: " + errorString)
        }
    }
    
    // Image capture component
    ImageCapture {
        id: imageCapture
        
        onImageSaved: function(id, path) {
            photoCount++
            Logger.info("Camera", "Photo saved: " + path)
            if (typeof MediaLibraryManager !== 'undefined') {
                MediaLibraryManager.scanLibrary()
            }
        }
        
        onErrorOccurred: function(id, error, errorString) {
            Logger.error("Camera", "Image capture error: " + errorString)
        }
    }
    
    // Video recording component
    MediaRecorder {
        id: mediaRecorder
        
        onRecorderStateChanged: function(state) {
            if (state === MediaRecorder.RecordingState) {
                isRecording = true
            } else if (state === MediaRecorder.StoppedState) {
                isRecording = false
            }
        }
        
        onErrorOccurred: function(error, errorString) {
            Logger.error("Camera", "Video recording error: " + errorString)
            isRecording = false
        }
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        // Full-screen camera viewfinder
        VideoOutput {
            id: viewfinder
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectCrop
        }
        
        // Recording time indicator
        Rectangle {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: Constants.spacingLarge
            width: Constants.touchTargetLarge * 2
            height: Constants.touchTargetMedium
            radius: Constants.borderRadiusSharp
            color: "#80000000"
            visible: isRecording
            
            Row {
                anchors.centerIn: parent
                spacing: Constants.spacingSmall
                
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Constants.spacingMedium
                    height: Constants.spacingMedium
                    radius: width / 2
                    color: MColors.error
                    
                    SequentialAnimation on opacity {
                        running: isRecording
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.0; duration: 500 }
                        NumberAnimation { from: 0.0; to: 1.0; duration: 500 }
                    }
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.floor(recordingSeconds / 60) + ":" + (recordingSeconds % 60 < 10 ? "0" : "") + (recordingSeconds % 60)
                    font.pixelSize: Constants.fontSizeLarge
                    font.weight: Font.Bold
                    color: "white"
                }
            }
        }
        
        // Setup capture session after viewfinder is created
        Component.onCompleted: {
            captureSession = Qt.createQmlObject('
                import QtMultimedia
                CaptureSession {
                    camera: camera
                    imageCapture: imageCapture
                    recorder: mediaRecorder
                    videoOutput: viewfinder
                }
            ', cameraApp)
        }
        
        // Dark overlay for better UI contrast
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.3
        }
        
        // Top controls
        Row {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: Constants.spacingLarge
            spacing: Constants.spacingSmall
            z: 10
            
            Rectangle {
                width: Constants.touchTargetMedium * 2.5
                height: Constants.touchTargetMedium
                radius: Constants.borderRadiusSharp
                color: currentMode === "photo" ? MColors.accent : "transparent"
                border.width: Constants.borderWidthThin
                border.color: currentMode === "photo" ? MColors.accentDark : MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Text {
                    anchors.centerIn: parent
                    text: "PHOTO"
                    font.pixelSize: Constants.fontSizeSmall
                    font.weight: Font.Bold
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        HapticService.light()
                    }
                    onClicked: {
                        currentMode = "photo"
                    }
                }
            }
            
            Rectangle {
                width: Constants.touchTargetMedium * 2.5
                height: Constants.touchTargetMedium
                radius: Constants.borderRadiusSharp
                color: currentMode === "video" ? MColors.accent : "transparent"
                border.width: Constants.borderWidthThin
                border.color: currentMode === "video" ? MColors.accentDark : MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Text {
                    anchors.centerIn: parent
                    text: "VIDEO"
                    font.pixelSize: Constants.fontSizeSmall
                    font.weight: Font.Bold
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        HapticService.light()
                    }
                    onClicked: {
                        currentMode = "video"
                    }
                }
            }
        }
        
        // Top right controls
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Constants.spacingLarge
            anchors.rightMargin: Constants.spacingLarge
            spacing: Constants.spacingMedium
            z: 10
            
            Rectangle {
                width: Constants.touchTargetMedium
                height: Constants.touchTargetMedium
                radius: Constants.borderRadiusSharp
                color: flashEnabled ? MColors.accent : "transparent"
                border.width: Constants.borderWidthThin
                border.color: flashEnabled ? MColors.accentDark : MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Icon {
                    anchors.centerIn: parent
                    name: flashEnabled ? "zap" : "zap-off"
                    size: Constants.iconSizeMedium
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        HapticService.light()
                    }
                    onClicked: {
                        flashEnabled = !flashEnabled
                        if (camera.cameraDevice && camera.cameraDevice.flashMode !== undefined) {
                            camera.flashMode = flashEnabled ? Camera.FlashOn : Camera.FlashOff
                        }
                    }
                }
            }
            
            Rectangle {
                width: Constants.touchTargetMedium
                height: Constants.touchTargetMedium
                radius: Constants.borderRadiusSharp
                color: "transparent"
                border.width: Constants.borderWidthThin
                border.color: MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Icon {
                    anchors.centerIn: parent
                    name: "settings"
                    size: Constants.iconSizeMedium
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        HapticService.light()
                    }
                    onClicked: {
                        Logger.info("Camera", "Settings clicked")
                    }
                }
            }
        }
        
        // Bottom controls
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Constants.spacingXLarge
            spacing: Constants.spacingXLarge
            z: 10
            
            // Gallery button
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Constants.touchTargetMedium
                height: Constants.touchTargetMedium
                radius: Constants.borderRadiusSharp
                color: MColors.surface
                border.width: Constants.borderWidthMedium
                border.color: MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Icon {
                    anchors.centerIn: parent
                    name: "image"
                    size: Constants.iconSizeMedium
                    color: MColors.accent
                }
                
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: -Constants.spacingXSmall
                    width: Constants.iconSizeSmall + Constants.spacingSmall
                    height: Constants.iconSizeSmall + Constants.spacingSmall
                    radius: width / 2
                    color: MColors.accent
                    visible: photoCount > 0
                    
                    Text {
                        anchors.centerIn: parent
                        text: photoCount
                        font.pixelSize: Constants.fontSizeXSmall
                        font.weight: Font.Bold
                        color: MColors.text
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        parent.color = MColors.surface2
                        HapticService.light()
                    }
                    onReleased: {
                        parent.color = MColors.surface
                    }
                    onCanceled: {
                        parent.color = MColors.surface
                    }
                    onClicked: {
                        Logger.info("Camera", "Open gallery")
                    }
                }
            }
            
            // Main capture button
            Rectangle {
                width: Constants.touchTargetLarge + Constants.spacingMedium
                height: Constants.touchTargetLarge + Constants.spacingMedium
                radius: width / 2
                color: "transparent"
                border.width: Constants.borderWidthThick
                border.color: isRecording ? MColors.error : MColors.accent
                antialiasing: true
                
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - Constants.spacingMedium
                    height: parent.height - Constants.spacingMedium
                    radius: width / 2
                    color: isRecording ? MColors.error : MColors.accent
                    antialiasing: true
                }
                
                // Recording indicator
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.3
                    height: parent.height * 0.3
                    radius: 4
                    color: MColors.text
                    visible: isRecording
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        parent.scale = 0.9
                        HapticService.medium()
                    }
                    onReleased: {
                        parent.scale = 1.0
                    }
                    onCanceled: {
                        parent.scale = 1.0
                    }
                    onClicked: {
                        if (currentMode === "photo") {
                            imageCapture.capture()
                            Logger.info("Camera", "Photo taken")
                        } else {
                            if (isRecording) {
                                mediaRecorder.stop()
                                isRecording = false
                                recordingSeconds = 0
                                Logger.info("Camera", "Video recording stopped")
                            } else {
                                mediaRecorder.outputLocation = "file://" + savePath + "/VID_" + Date.now() + ".mp4"
                                mediaRecorder.record()
                                isRecording = true
                                recordingSeconds = 0
                                Logger.info("Camera", "Video recording started")
                            }
                        }
                    }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 100 }
                }
            }
            
            // Camera switch button
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Constants.touchTargetMedium
                height: Constants.touchTargetMedium
                radius: Constants.borderRadiusSharp
                color: "transparent"
                border.width: Constants.borderWidthThin
                border.color: MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Icon {
                    anchors.centerIn: parent
                    name: "refresh-cw"
                    size: Constants.iconSizeMedium
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        parent.color = MColors.surface
                        HapticService.light()
                    }
                    onReleased: {
                        parent.color = "transparent"
                    }
                    onCanceled: {
                        parent.color = "transparent"
                    }
                    onClicked: {
                        frontCamera = !frontCamera
                        
                        // Switch camera device
                        if (mediaDevices.videoInputs.length > 1) {
                            var currentIndex = -1
                            for (var i = 0; i < mediaDevices.videoInputs.length; i++) {
                                if (mediaDevices.videoInputs[i].id === camera.cameraDevice.id) {
                                    currentIndex = i
                                    break
                                }
                            }
                            var nextIndex = (currentIndex + 1) % mediaDevices.videoInputs.length
                            camera.cameraDevice = mediaDevices.videoInputs[nextIndex]
                            Logger.info("Camera", "Switched to camera: " + camera.cameraDevice.description)
                        }
                    }
                }
            }
        }
        
        // Recording indicator
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: Constants.spacingLarge
            width: 12
            height: 12
            radius: 6
            color: MColors.error
            visible: isRecording
            z: 10
            
            SequentialAnimation on opacity {
                running: isRecording
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 500 }
                NumberAnimation { to: 1.0; duration: 500 }
            }
        }
    }
}
