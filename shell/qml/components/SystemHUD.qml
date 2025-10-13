import QtQuick
import MarathonOS.Shell
import "../MarathonUI/Theme"

Item {
    id: hudContainer
    anchors.fill: parent
    z: 2900
    
    property string hudType: "volume"
    property real hudValue: 0
    property bool hudVisible: false
    
    function showVolume(value) {
        hudType = "volume"
        hudValue = value
        show()
    }
    
    function showBrightness(value) {
        hudType = "brightness"
        hudValue = value
        show()
    }
    
    function show() {
        hudVisible = true
        hud.opacity = 1
        autoHideTimer.restart()
    }
    
    function hide() {
        hudVisible = false
        fadeOut.start()
    }
    
    Rectangle {
        id: hud
        anchors.centerIn: parent
        width: 200
        height: 200
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.95)
        border.width: 1
        border.color: Qt.rgba(255/255, 255/255, 255/255, 0.15)
        layer.enabled: true
        opacity: 0
        visible: hudVisible
        
        Behavior on opacity {
            NumberAnimation { 
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.05)
        }
        
        Column {
            anchors.centerIn: parent
            spacing: 20
            width: parent.width - 40
            
            Icon {
                name: hudType === "volume" ? "volume-2" : "sun"
                size: 64
                color: Colors.text
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Column {
                width: parent.width
                spacing: 8
                
                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.1)
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.05)
                    
                    Rectangle {
                        width: parent.width * hudValue
                        height: parent.height
                        radius: parent.radius
                        color: Qt.rgba(20/255, 184/255, 166/255, 0.9)
                        
                        Behavior on width {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
                
                Text {
                    text: Math.round(hudValue * 100) + "%"
                    color: Colors.text
                    font.pixelSize: Typography.sizeLarge
                    font.weight: Font.DemiBold
                    font.family: Typography.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
    
    Timer {
        id: autoHideTimer
        interval: 2000
        onTriggered: hide()
    }
    
    NumberAnimation {
        id: fadeOut
        target: hud
        property: "opacity"
        to: 0
        duration: 200
        easing.type: Easing.InCubic
    }
}

