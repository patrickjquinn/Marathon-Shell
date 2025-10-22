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
    property bool keyboardVisible: false  // Set by parent
    
    signal appLaunched(var app)
    signal toggleKeyboard()
    
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
        anchors.leftMargin: Constants.spacingXLarge
        anchors.verticalCenter: parent.verticalCenter
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 10
        
        Image {
            source: "qrc:/images/phone.svg"
            width: Constants.iconSizeMedium
            height: Constants.iconSizeMedium
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
            width: bottomBar.currentPage === -2 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: bottomBar.currentPage === -2 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: Colors.cornerRadiusCircle  // BB10: True circle
            color: bottomBar.currentPage === -2 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter
            
            Behavior on width { NumberAnimation { duration: 200 } }
            Behavior on height { NumberAnimation { duration: 200 } }
            Behavior on color { ColorAnimation { duration: 200 } }
            
            Image {
                source: bottomBar.currentPage === -2 ? "qrc:/images/icons/lucide/inbox-black.svg" : "qrc:/images/icons/lucide/inbox.svg"
                width: bottomBar.currentPage === -2 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                height: bottomBar.currentPage === -2 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
                smooth: true
                antialiasing: true
                
                Behavior on width { NumberAnimation { duration: 200 } }
                Behavior on height { NumberAnimation { duration: 200 } }
            }
        }
        
        Rectangle {
            width: bottomBar.currentPage === -1 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: bottomBar.currentPage === -1 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: Colors.cornerRadiusCircle  // BB10: True circle
            color: bottomBar.currentPage === -1 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter
            
            Behavior on width { NumberAnimation { duration: 200 } }
            Behavior on height { NumberAnimation { duration: 200 } }
            Behavior on color { ColorAnimation { duration: 200 } }
            
            Image {
                source: bottomBar.currentPage === -1 ? "qrc:/images/icons/lucide/grid-black.svg" : "qrc:/images/icons/lucide/grid.svg"
                width: bottomBar.currentPage === -1 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                height: bottomBar.currentPage === -1 ? Constants.iconSizeSmall : Constants.fontSizeSmall
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
                width: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                height: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                radius: Colors.cornerRadiusCircle  // BB10: True circle
                color: index === bottomBar.currentPage ? "#FFFFFF" : "#444444"
                anchors.verticalCenter: parent.verticalCenter
                
                Behavior on width { NumberAnimation { duration: 200 } }
                Behavior on height { NumberAnimation { duration: 200 } }
                Behavior on color { ColorAnimation { duration: 200 } }
                
                Text {
                    text: (index + 1).toString()
                    color: index === bottomBar.currentPage ? "#000000" : "#FFFFFF"
                    font.pixelSize: index === bottomBar.currentPage ? Constants.fontSizeSmall : Constants.fontSizeXSmall
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
        anchors.rightMargin: Constants.spacingXLarge
        anchors.verticalCenter: parent.verticalCenter
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 10
        
        Image {
            source: "qrc:/images/camera.svg"
            width: Constants.iconSizeMedium
            height: Constants.iconSizeMedium
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
    
    Item {
        id: keyboardShortcut
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingXLarge
        anchors.verticalCenter: parent.verticalCenter
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 10
        
        Rectangle {
            anchors.fill: parent
            radius: Constants.borderRadiusSmall
            color: bottomBar.keyboardVisible ? MColors.accent : "transparent"
            opacity: bottomBar.keyboardVisible ? 0.2 : 0
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
        }
        
        Icon {
            name: "file-text"
            size: Constants.iconSizeMedium
            color: bottomBar.keyboardVisible ? MColors.accent : MColors.text
            anchors.centerIn: parent
            opacity: keyboardMouseArea.pressed ? 0.6 : 1.0
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }
        
        MouseArea {
            id: keyboardMouseArea
            anchors.fill: parent
            anchors.margins: -Constants.spacingSmall  // Larger tap target
            onClicked: {
                HapticService.light()
                bottomBar.toggleKeyboard()
            }
        }
    }
}

