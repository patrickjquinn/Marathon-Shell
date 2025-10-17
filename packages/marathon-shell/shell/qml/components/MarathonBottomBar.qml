import QtQuick
import MarathonOS.Shell
import "."

Item {
    id: bottomBar
    height: Constants.bottomBarHeight
    
    property int currentPage: 0
    property int totalPages: 1
    property bool showNotifications: currentPage >= 0
    property bool showPageIndicators: true
    
    signal appLaunched(var app)
    
    Component.onCompleted: Logger.info("BottomBar", "Initialized")
    
    Rectangle {
        id: background
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: WallpaperStore.isDark ? "#80000000" : "#80FFFFFF" }
        }
        z: Constants.zIndexBackground
    }
    
    Item {
        id: phoneShortcut
        anchors.left: parent.left
        anchors.leftMargin: 30
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        height: 48
        z: 10
        
        Image {
            source: "qrc:/images/phone.svg"
            width: 32
            height: 32
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
            asynchronous: true
            cache: true
            opacity: phoneMouseArea.pressed ? 0.6 : 1.0
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
        
        MouseArea {
            id: phoneMouseArea
            anchors.fill: parent
            onClicked: {
                var app = { id: "phone", name: "Phone", icon: "qrc:/images/phone.svg" }
                appLaunched(app)
            }
        }
    }
    
    Row {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0
        spacing: Constants.spacingMedium
        z: 1
        visible: bottomBar.showPageIndicators
        
        Rectangle {
            width: bottomBar.currentPage === -2 ? 40 : 20
            height: bottomBar.currentPage === -2 ? 40 : 20
            radius: Colors.cornerRadiusCircle  // BB10: True circle
            color: bottomBar.currentPage === -2 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter
            
            Behavior on width { NumberAnimation { duration: 200 } }
            Behavior on height { NumberAnimation { duration: 200 } }
            Behavior on color { ColorAnimation { duration: 200 } }
            
            Image {
                source: bottomBar.currentPage === -2 ? "qrc:/images/icons/lucide/inbox-black.svg" : "qrc:/images/icons/lucide/inbox.svg"
                width: bottomBar.currentPage === -2 ? 20 : 14
                height: bottomBar.currentPage === -2 ? 20 : 14
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
                smooth: true
                antialiasing: true
                
                Behavior on width { NumberAnimation { duration: 200 } }
                Behavior on height { NumberAnimation { duration: 200 } }
            }
        }
        
        Rectangle {
            width: bottomBar.currentPage === -1 ? 40 : 20
            height: bottomBar.currentPage === -1 ? 40 : 20
            radius: Colors.cornerRadiusCircle  // BB10: True circle
            color: bottomBar.currentPage === -1 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter
            
            Behavior on width { NumberAnimation { duration: 200 } }
            Behavior on height { NumberAnimation { duration: 200 } }
            Behavior on color { ColorAnimation { duration: 200 } }
            
            Image {
                source: bottomBar.currentPage === -1 ? "qrc:/images/icons/lucide/grid-black.svg" : "qrc:/images/icons/lucide/grid.svg"
                width: bottomBar.currentPage === -1 ? 20 : 14
                height: bottomBar.currentPage === -1 ? 20 : 14
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
                smooth: true
                antialiasing: true
                
                Behavior on width { NumberAnimation { duration: 200 } }
                Behavior on height { NumberAnimation { duration: 200 } }
            }
        }
        
        Repeater {
            model: bottomBar.totalPages
            
            Rectangle {
                width: index === bottomBar.currentPage ? 28 : 16
                height: index === bottomBar.currentPage ? 28 : 16
                radius: Colors.cornerRadiusCircle  // BB10: True circle
                color: index === bottomBar.currentPage ? "#FFFFFF" : "#444444"
                anchors.verticalCenter: parent.verticalCenter
                
                Behavior on width { NumberAnimation { duration: 200 } }
                Behavior on height { NumberAnimation { duration: 200 } }
                Behavior on color { ColorAnimation { duration: 200 } }
                
                Text {
                    text: (index + 1).toString()
                    color: index === bottomBar.currentPage ? "#000000" : "#FFFFFF"
                    font.pixelSize: index === bottomBar.currentPage ? 14 : 10
                    font.weight: Font.Medium
                    anchors.centerIn: parent
                    
                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                    Behavior on font.pixelSize {
                        NumberAnimation { duration: 200 }
                    }
                }
            }
        }
    }
    
    Item {
        id: cameraShortcut
        anchors.right: parent.right
        anchors.rightMargin: 30
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        height: 48
        z: 10
        
        Image {
            source: "qrc:/images/camera.svg"
            width: 32
            height: 32
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            anchors.centerIn: parent
            opacity: cameraMouseArea.pressed ? 0.6 : 1.0
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
        
        MouseArea {
            id: cameraMouseArea
            anchors.fill: parent
            onClicked: {
                var app = { id: "camera", name: "Camera", icon: "qrc:/images/camera.svg" }
                appLaunched(app)
            }
        }
    }
}

