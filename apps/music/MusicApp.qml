import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme

MApp {
    id: musicApp
    appId: "music"
    appName: "Music"
    appIcon: "assets/icon.svg"
    
    property var currentTrack: {
        "title": "Midnight Drive",
        "artist": "The Weekend Vibes",
        "album": "Neon Nights",
        "duration": 243,
        "position": 67
    }
    
    property bool isPlaying: false
    property bool shuffle: false
    property string repeatMode: "off"
    
    property var playlist: [
        { title: "Midnight Drive", artist: "The Weekend Vibes", album: "Neon Nights", duration: 243 },
        { title: "Starlight Symphony", artist: "Luna Eclipse", album: "Cosmic Dreams", duration: 198 },
        { title: "Urban Rhythm", artist: "City Beats", album: "Street Stories", duration: 215 },
        { title: "Ocean Waves", artist: "Ambient Collective", album: "Nature Sounds", duration: 312 },
        { title: "Electric Dreams", artist: "Synthwave Masters", album: "Retro Future", duration: 267 }
    ]
    
    function formatTime(seconds) {
        var mins = Math.floor(seconds / 60)
        var secs = seconds % 60
        return mins + ":" + (secs < 10 ? "0" : "") + secs
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
                
                Rectangle {
                    color: MColors.background
                    
                    Column {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingXLarge
                        spacing: Constants.spacingLarge
                        
                        Item { height: Constants.spacingLarge }
                        
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, parent.height * 0.5)
                            height: width
                            radius: Constants.borderRadiusSharp
                            color: MColors.surface
                            border.width: Constants.borderWidthThick
                            border.color: MColors.border
                            antialiasing: Constants.enableAntialiasing
                            
                            Icon {
                                anchors.centerIn: parent
                                name: "music-2"
                                size: Constants.iconSizeXLarge * 2
                                color: MColors.accent
                            }
                            
                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 10000
                                loops: Animation.Infinite
                                running: isPlaying
                            }
                        }
                        
                        Item { height: Constants.spacingMedium }
                        
                        Column {
                            width: parent.width
                            spacing: Constants.spacingSmall
                            
                            Text {
                                width: parent.width
                                text: currentTrack.title
                                font.pixelSize: Constants.fontSizeXLarge
                                font.weight: Font.Bold
                                color: MColors.text
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            
                            Text {
                                width: parent.width
                                text: currentTrack.artist
                                font.pixelSize: Constants.fontSizeLarge
                                color: MColors.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            
                            Text {
                                width: parent.width
                                text: currentTrack.album
                                font.pixelSize: Constants.fontSizeMedium
                                color: MColors.textTertiary
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                        
                        Item { height: Constants.spacingMedium }
                        
                           Column {
                               width: parent.width
                               spacing: Constants.spacingSmall

                               MSlider {
                                   width: parent.width
                                   from: 0
                                   to: currentTrack.duration
                                   value: currentTrack.position
                                   onMoved: {
                                       currentTrack.position = value
                                   }
                               }

                               Row {
                                   width: parent.width

                                   Text {
                                       text: formatTime(currentTrack.position)
                                       font.pixelSize: Constants.fontSizeSmall
                                       color: MColors.textSecondary
                                   }

                                   Item {
                                       width: parent.width - parent.children[0].width - parent.children[2].width
                                       height: 1
                                   }

                                   Text {
                                       text: formatTime(currentTrack.duration)
                                       font.pixelSize: Constants.fontSizeSmall
                                       color: MColors.textSecondary
                                   }
                               }
                           }
                        
                        Item { height: Constants.spacingMedium }
                        
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Constants.spacingLarge
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetMedium
                                height: Constants.touchTargetMedium
                                radius: Constants.borderRadiusSharp
                                color: shuffle ? MColors.accent : "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: shuffle ? MColors.accentDark : MColors.border
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "shuffle"
                                    size: Constants.iconSizeMedium
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        HapticService.light()
                                    }
                                    onClicked: {
                                        shuffle = !shuffle
                                    }
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
                                    name: "skip-back"
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
                                        console.log("Previous track")
                                    }
                                }
                            }
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetLarge
                                height: Constants.touchTargetLarge
                                radius: width / 2
                                color: MColors.accent
                                border.width: Constants.borderWidthMedium
                                border.color: MColors.accentDark
                                antialiasing: true
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: isPlaying ? "pause" : "play"
                                    size: Constants.iconSizeLarge
                                    color: MColors.text
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
                                        isPlaying = !isPlaying
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
                                    name: "skip-forward"
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
                                        console.log("Next track")
                                    }
                                }
                            }
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetMedium
                                height: Constants.touchTargetMedium
                                radius: Constants.borderRadiusSharp
                                color: repeatMode !== "off" ? MColors.accent : "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: repeatMode !== "off" ? MColors.accentDark : MColors.border
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: repeatMode === "one" ? "repeat-1" : "repeat"
                                    size: Constants.iconSizeMedium
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        HapticService.light()
                                    }
                                    onClicked: {
                                        if (repeatMode === "off") {
                                            repeatMode = "all"
                                        } else if (repeatMode === "all") {
                                            repeatMode = "one"
                                        } else {
                                            repeatMode = "off"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                ListView {
                    width: parent.width
                    height: parent.height
                    clip: true
                    
                    model: playlist
                    
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: Constants.touchTargetLarge + Constants.spacingSmall
                        color: "transparent"
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            anchors.topMargin: 0
                            color: MColors.surface
                            radius: Constants.borderRadiusSharp
                            border.width: Constants.borderWidthThin
                            border.color: index === 0 ? MColors.accent : MColors.border
                            antialiasing: Constants.enableAntialiasing
                            
                            Row {
                                anchors.fill: parent
                                anchors.margins: Constants.spacingMedium
                                spacing: Constants.spacingMedium
                                
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.iconSizeLarge + Constants.spacingMedium
                                    height: Constants.iconSizeLarge + Constants.spacingMedium
                                    radius: Constants.borderRadiusSharp
                                    color: MColors.surface2
                                    border.width: Constants.borderWidthThin
                                    border.color: MColors.border
                                    antialiasing: Constants.enableAntialiasing
                                    
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "music-2"
                                        size: Constants.iconSizeMedium
                                        color: MColors.accent
                                    }
                                }
                                
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 3 - Constants.iconSizeLarge - Constants.spacingMedium - 40
                                    spacing: Constants.spacingXSmall
                                    
                                    Text {
                                        width: parent.width
                                        text: modelData.title
                                        font.pixelSize: Constants.fontSizeMedium
                                        font.weight: index === 0 ? Font.Bold : Font.DemiBold
                                        color: index === 0 ? MColors.accent : MColors.text
                                        elide: Text.ElideRight
                                    }
                                    
                                    Row {
                                        spacing: Constants.spacingSmall
                                        
                                        Text {
                                            text: modelData.artist
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                        
                                        Text {
                                            text: "•"
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                        
                                        Text {
                                            text: formatTime(modelData.duration)
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                    }
                                }
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: index === 0 && isPlaying ? "pause" : "play"
                                    size: Constants.iconSizeMedium
                                    color: index === 0 ? MColors.accent : MColors.textTertiary
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
                                    console.log("Play track:", modelData.title)
                                }
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
                            { icon: "disc", label: "Now Playing" },
                            { icon: "library", label: "Library" }
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
