import QtQuick
import QtQuick.Controls
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
    
    content: Rectangle {
        anchors.fill: parent
        color: "#1A1A1A"
        
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthMedium
            border.color: MColors.border
            antialiasing: Constants.enableAntialiasing
            
            Column {
                anchors.centerIn: parent
                spacing: Constants.spacingMedium
                
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "camera"
                    size: Constants.iconSizeXLarge
                    color: MColors.textSecondary
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Camera Viewfinder"
                    font.pixelSize: Constants.fontSizeMedium
                    color: MColors.textSecondary
                }
            }
        }
        
        Row {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: Constants.spacingLarge
            spacing: Constants.spacingSmall
            
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
        
        Row {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Constants.spacingLarge
            spacing: Constants.spacingMedium
            
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
                        console.log("Camera settings")
                    }
                }
            }
        }
        
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: Constants.spacingXLarge
            spacing: Constants.spacingXLarge
            
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
                        console.log("Open gallery")
                    }
                }
            }
            
            Rectangle {
                width: Constants.touchTargetLarge + Constants.spacingMedium
                height: Constants.touchTargetLarge + Constants.spacingMedium
                radius: width / 2
                color: "transparent"
                border.width: Constants.borderWidthThick
                border.color: MColors.accent
                antialiasing: true
                
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - Constants.spacingMedium
                    height: parent.height - Constants.spacingMedium
                    radius: width / 2
                    color: MColors.accent
                    antialiasing: true
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
                            photoCount++
                            console.log("Photo taken")
                        } else {
                            console.log("Video recording")
                        }
                    }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 100 }
                }
            }
            
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
                        console.log("Switch camera")
                    }
                }
            }
        }
    }
}
