import QtQuick
import MarathonOS.Shell

Item {
    id: screenshotPreview
    anchors.fill: parent
    z: 2700
    
    property bool showing: false
    property string filePath: ""
    property var thumbnail: null
    
    function show(path, image) {
        filePath = path
        thumbnail = image
        showing = true
        slideIn.start()
        autoHideTimer.restart()
    }
    
    function hide() {
        slideOut.start()
    }
    
    Rectangle {
        id: previewCard
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.bottomMargin: Constants.navBarHeight + Constants.bottomBarHeight + 16
        anchors.rightMargin: Constants.spacingMedium
        width: 160
        height: Constants.touchTargetLarge
        radius: 4
        color: Qt.rgba(15, 15, 15, 0.98)
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.15)
        layer.enabled: true
        visible: showing
        opacity: 0
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.05)
        }
        
        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6
            
            Rectangle {
                width: parent.width
                height: parent.height - 20
                radius: 2
                color: "#000000"
                clip: true
                
                Image {
                    anchors.fill: parent
                    source: thumbnail || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
            }
            
            Text {
                text: "Screenshot saved"
                color: Colors.text
                font.pixelSize: 10
                font.family: Typography.fontFamily
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                Logger.info("ScreenshotPreview", "Opening screenshot: " + filePath)
                hide()
            }
            
            property real startX: 0
            
            onPressed: (mouse) => {
                startX = mouse.x
            }
            
            onPositionChanged: (mouse) => {
                if (mouse.x - startX > 50) {
                    hide()
                }
            }
        }
    }
    
    NumberAnimation {
        id: slideIn
        target: previewCard
        property: "opacity"
        from: 0
        to: 1
        duration: 250
        easing.type: Easing.OutCubic
    }
    
    NumberAnimation {
        id: slideOut
        target: previewCard
        property: "opacity"
        to: 0
        duration: 200
        easing.type: Easing.InCubic
        onFinished: {
            showing = false
        }
    }
    
    Timer {
        id: autoHideTimer
        interval: 3000
        onTriggered: hide()
    }
    
    Rectangle {
        id: flashOverlay
        anchors.fill: parent
        color: "#FFFFFF"
        opacity: 0
        z: 3100
        
        SequentialAnimation {
            id: flashAnimation
            NumberAnimation {
                target: flashOverlay
                property: "opacity"
                to: 0.8
                duration: 50
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: flashOverlay
                property: "opacity"
                to: 0
                duration: 200
                easing.type: Easing.InCubic
            }
        }
    }
    
    Connections {
        target: ScreenshotService
        function onScreenshotCaptured(path, image) {
            flashAnimation.start()
            screenshotPreview.show(path, image)
        }
    }
}

