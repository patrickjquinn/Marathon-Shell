import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import "./pages"

MApp {
    id: galleryApp
    appId: "gallery"
    appName: "Gallery"
    appIcon: "assets/icon.svg"
    
    property var albums: typeof MediaLibraryManager !== 'undefined' ? MediaLibraryManager.albums : []
    property var photos: []
    property string selectedAlbum: ""
    
    Component.onCompleted: {
        if (typeof MediaLibraryManager !== 'undefined') {
            MediaLibraryManager.scanLibrary()
        }
    }
    
    Connections {
        target: typeof MediaLibraryManager !== 'undefined' ? MediaLibraryManager : null
        function onScanComplete(photoCount, videoCount) {
            Logger.info("Gallery", "Library scan complete: " + photoCount + " photos, " + videoCount + " videos")
        }
    }
    
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
                                            text: modelData.photoCount + " photos"
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
                                        Logger.info("Gallery", "Open album: " + modelData.name)
                                        selectedAlbum = modelData.id
                                        if (typeof MediaLibraryManager !== 'undefined') {
                                            photos = MediaLibraryManager.getPhotos(modelData.id)
                                        }
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
                    
                    model: photos
                    
                    delegate: Rectangle {
                        width: GridView.view.cellWidth - Constants.spacingXSmall
                        height: GridView.view.cellHeight - Constants.spacingXSmall
                        color: MColors.surface
                        radius: Constants.borderRadiusSharp
                        border.width: Constants.borderWidthThin
                        border.color: MColors.border
                        antialiasing: Constants.enableAntialiasing
                        
                        Image {
                            anchors.fill: parent
                            anchors.margins: Constants.borderWidthThin
                            source: modelData.thumbnailPath || modelData.path
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            clip: true
                            
                            Rectangle {
                                anchors.fill: parent
                                color: MColors.surface2
                                radius: Constants.borderRadiusSharp
                                visible: parent.status === Image.Loading || parent.status === Image.Error
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "image"
                                    size: Constants.iconSizeLarge
                                    color: MColors.textSecondary
                                }
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
                                Logger.info("Gallery", "View photo: " + modelData.id)
                                photoViewerLoader.active = true
                                photoViewerLoader.item.show(modelData)
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
    
    Loader {
        id: photoViewerLoader
        anchors.fill: parent
        active: false
        sourceComponent: PhotoViewerPage {}
    }
}
