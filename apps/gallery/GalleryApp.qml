import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

MApp {
    id: galleryApp
    appId: "gallery"
    appName: "Gallery"
    appIcon: "assets/icon.svg"
    
    property var albums: [
        { name: "Camera Roll", count: 47, thumbnail: 0 },
        { name: "Screenshots", count: 23, thumbnail: 1 },
        { name: "Favorites", count: 12, thumbnail: 2 },
        { name: "Vacation 2024", count: 156, thumbnail: 3 }
    ]
    
    property var photos: [
        { id: 1, album: "Camera Roll", timestamp: Date.now() - 1000 * 60 * 60 },
        { id: 2, album: "Camera Roll", timestamp: Date.now() - 1000 * 60 * 60 * 2 },
        { id: 3, album: "Camera Roll", timestamp: Date.now() - 1000 * 60 * 60 * 24 },
        { id: 4, album: "Screenshots", timestamp: Date.now() - 1000 * 60 * 60 * 24 * 2 },
        { id: 5, album: "Favorites", timestamp: Date.now() - 1000 * 60 * 60 * 24 * 3 },
        { id: 6, album: "Vacation 2024", timestamp: Date.now() - 1000 * 60 * 60 * 24 * 7 }
    ]
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            property int currentView: 0
            
            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentView
                
                ScrollView {
                    width: parent.width
                    height: parent.height
                    contentWidth: width
                    clip: true
                    
                    Column {
                        width: parent.width
                        padding: Constants.spacingMedium
                        spacing: Constants.spacingMedium
                        
                        Repeater {
                            model: albums
                            
                            Rectangle {
                                width: parent.width - parent.padding * 2
                                height: Constants.touchTargetLarge * 1.5
                                color: MColors.surface
                                radius: Constants.borderRadiusSharp
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border
                                antialiasing: Constants.enableAntialiasing
                                
                                Row {
                                    anchors.fill: parent
                                    anchors.margins: Constants.spacingMedium
                                    spacing: Constants.spacingMedium
                                    
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Constants.touchTargetLarge
                                        height: Constants.touchTargetLarge
                                        radius: Constants.borderRadiusSharp
                                        color: MColors.surface2
                                        border.width: Constants.borderWidthMedium
                                        border.color: MColors.border
                                        antialiasing: Constants.enableAntialiasing
                                        
                                        Icon {
                                            anchors.centerIn: parent
                                            name: "image"
                                            size: Constants.iconSizeLarge
                                            color: MColors.accent
                                        }
                                    }
                                    
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - parent.spacing * 2 - Constants.touchTargetLarge - Constants.iconSizeMedium
                                        spacing: Constants.spacingXSmall
                                        
                                        Text {
                                            text: modelData.name
                                            font.pixelSize: Constants.fontSizeMedium
                                            font.weight: Font.DemiBold
                                            color: MColors.text
                                        }
                                        
                                        Text {
                                            text: modelData.count + " photos"
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                    }
                                    
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "chevron-right"
                                        size: Constants.iconSizeMedium
                                        color: MColors.textTertiary
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
                                        console.log("Open album:", modelData.name)
                                        parent.parent.parent.parent.parent.parent.parent.currentView = 1
                                    }
                                }
                            }
                        }
                    }
                }
                
                GridView {
                    width: parent.width
                    height: parent.height
                    cellWidth: width / 3
                    cellHeight: cellWidth
                    clip: true
                    
                    model: 12
                    
                    delegate: Rectangle {
                        width: GridView.view.cellWidth - Constants.spacingXSmall
                        height: GridView.view.cellHeight - Constants.spacingXSmall
                        color: MColors.surface
                        radius: Constants.borderRadiusSharp
                        border.width: Constants.borderWidthThin
                        border.color: MColors.border
                        antialiasing: Constants.enableAntialiasing
                        
                        Icon {
                            anchors.centerIn: parent
                            name: "image"
                            size: Constants.iconSizeLarge
                            color: MColors.textSecondary
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
                                console.log("View photo:", index)
                            }
                        }
                    }
                }
            }
            
            Rectangle {
                id: tabBar
                width: parent.width
                height: Constants.actionBarHeight
                color: MColors.surface
                
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }
                
                Row {
                    anchors.fill: parent
                    spacing: 0
                    
                    Repeater {
                        model: [
                            { icon: "folder", label: "Albums" },
                            { icon: "grid", label: "Photos" }
                        ]
                        
                        Rectangle {
                            width: tabBar.width / 2
                            height: tabBar.height
                            color: "transparent"
                            
                            Rectangle {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.8
                                height: Constants.borderWidthThick
                                color: MColors.accent
                                opacity: tabBar.parent.currentView === index ? 1.0 : 0.0
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: Constants.animationFast }
                                }
                            }
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: Constants.spacingXSmall
                                
                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: modelData.icon
                                    size: Constants.iconSizeMedium
                                    color: tabBar.parent.currentView === index ? MColors.accent : MColors.textSecondary
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                                
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: Constants.fontSizeXSmall
                                    color: tabBar.parent.currentView === index ? MColors.accent : MColors.textSecondary
                                    font.weight: tabBar.parent.currentView === index ? Font.DemiBold : Font.Normal
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light()
                                    tabBar.parent.currentView = index
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
