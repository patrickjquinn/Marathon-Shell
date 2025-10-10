import QtQuick
import "../theme"
import "../stores"
import "."

Item {
    id: bottomBar
    height: 100
    
    property int currentPage: 0
    property int totalPages: 1
    
    Component.onCompleted: console.log("✅ BOTTOM BAR LOADED")
    
    Rectangle {
        id: background
        anchors.fill: parent
        color: WallpaperStore.isDark ? "#000000" : "#FFFFFF"
        opacity: 0.3
        z: 0
        
        MouseArea {
            anchors.fill: parent
            onPressed: console.log("🟡 BOTTOM BAR PRESSED")
            onClicked: console.log("🟡 BOTTOM BAR CLICKED")
        }
    }
    
    Rectangle {
        id: phoneShortcut
        anchors.left: parent.left
        anchors.leftMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        width: 60
        height: 60
        radius: 30
        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, 0.6)
        border.color: Qt.rgba(Colors.accentLight.r, Colors.accentLight.g, Colors.accentLight.b, 0.5)
        border.width: 2
        z: 1
        
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.15) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.15) }
            }
        }
        
        Image {
            source: "qrc:/images/phone.svg"
            width: 32
            height: 32
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        
            MouseArea {
                anchors.fill: parent
                onPressed: console.log("📱 PHONE SHORTCUT PRESSED")
                onClicked: {
                    console.log("📱 PHONE SHORTCUT CLICKED")
                    AppStore.launchApp("phone")
                }
            }
    }
    
    Row {
        spacing: 16
        anchors.centerIn: parent
        z: 1
        
        Repeater {
            model: totalPages
            
            Rectangle {
                width: index === currentPage ? 16 : 12
                height: index === currentPage ? 16 : 12
                radius: width / 2
                color: index === currentPage ? Colors.accent : Colors.surface
                border.width: 1
                border.color: Colors.accentLight
                opacity: index === currentPage ? 1.0 : 0.6
                
                Behavior on width { NumberAnimation { duration: Theme.durationFast } }
                Behavior on height { NumberAnimation { duration: Theme.durationFast } }
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
            }
        }
    }
    
    Rectangle {
        id: cameraShortcut
        anchors.right: parent.right
        anchors.rightMargin: 40
        anchors.verticalCenter: parent.verticalCenter
        width: 60
        height: 60
        radius: 30
        color: Qt.rgba(Colors.surface.r, Colors.surface.g, Colors.surface.b, 0.6)
        border.color: Qt.rgba(Colors.accentLight.r, Colors.accentLight.g, Colors.accentLight.b, 0.5)
        border.width: 2
        z: 1
        
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.15) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.15) }
            }
        }
        
        Image {
            source: "qrc:/images/camera.svg"
            width: 32
            height: 32
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        
        MouseArea {
            anchors.fill: parent
            onPressed: console.log("📷 CAMERA SHORTCUT PRESSED")
            onClicked: {
                console.log("📷 CAMERA SHORTCUT CLICKED")
                AppStore.launchApp("camera")
            }
        }
    }
}

