import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

MApp {
    id: mapsApp
    appId: "maps"
    appName: "Maps"
    appIcon: "assets/icon.svg"
    
    property string currentLocation: "San Francisco, CA"
    property var searchResults: [
        { name: "Cafe Lumière", address: "123 Market St", distance: "0.3 mi", type: "cafe" },
        { name: "Central Park", address: "456 Park Ave", distance: "0.7 mi", type: "park" },
        { name: "Tech Museum", address: "789 Innovation Dr", distance: "1.2 mi", type: "museum" },
        { name: "Marina Harbor", address: "321 Waterfront Rd", distance: "2.5 mi", type: "landmark" }
    ]
    
    property bool showSearch: false
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Rectangle {
            id: mapView
            anchors.fill: parent
            color: "#2A2A2A"
            
            // Grid pattern for map
            Grid {
                anchors.fill: parent
                columns: 4
                rows: 6
                
                Repeater {
                    model: 24
                    
                    Rectangle {
                        width: mapView.width / 4
                        height: mapView.height / 6
                        color: index % 2 === 0 ? "#252525" : "#2F2F2F"
                        border.width: 1
                        border.color: "#1A1A1A"
                    }
                }
            }
            
            // Navigation icon in center
            Icon {
                anchors.centerIn: parent
                name: "navigation"
                size: Constants.iconSizeLarge
                color: MColors.accent
                rotation: 45
            }
            
            // Search bar
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Constants.spacingMedium
                height: Constants.touchTargetLarge
                color: MColors.surface
                radius: Constants.borderRadiusSharp
                border.width: Constants.borderWidthMedium
                border.color: MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Row {
                    anchors.fill: parent
                    anchors.margins: Constants.spacingMedium
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: Constants.iconSizeMedium
                        color: MColors.textSecondary
                    }
                    
                    TextInput {
                        id: searchInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.spacing * 3 - Constants.iconSizeMedium * 2
                        font.pixelSize: Constants.fontSizeMedium
                        color: MColors.text
                        verticalAlignment: TextInput.AlignVCenter
                        
                        onTextChanged: {
                            showSearch = text.length > 0
                        }
                        
                        Text {
                            anchors.fill: parent
                            text: "Search for places..."
                            font.pixelSize: Constants.fontSizeMedium
                            color: MColors.textSecondary
                            verticalAlignment: Text.AlignVCenter
                            visible: searchInput.text.length === 0
                        }
                    }
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: searchInput.text.length > 0 ? "x" : "map-pin"
                        size: Constants.iconSizeMedium
                        color: searchInput.text.length > 0 ? MColors.text : MColors.textSecondary
                        visible: true
                        
                        MouseArea {
                            anchors.fill: parent
                            visible: searchInput.text.length > 0
                            onClicked: {
                                searchInput.text = ""
                                showSearch = false
                                HapticService.light()
                            }
                        }
                    }
                }
            }
            
            // Map controls
            Column {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Constants.spacingMedium
                spacing: Constants.spacingSmall
                
                Rectangle {
                    width: Constants.touchTargetMedium
                    height: Constants.touchTargetMedium
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
                    Icon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: Constants.iconSizeMedium
                        color: MColors.text
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
                            console.log("Zoom in")
                        }
                    }
                }
                
                Rectangle {
                    width: Constants.touchTargetMedium
                    height: Constants.touchTargetMedium
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
                    Icon {
                        anchors.centerIn: parent
                        name: "minus"
                        size: Constants.iconSizeMedium
                        color: MColors.text
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
                            console.log("Zoom out")
                        }
                    }
                }
                
                Item { height: Constants.spacingMedium }
                
                Rectangle {
                    width: Constants.touchTargetMedium
                    height: Constants.touchTargetMedium
                    radius: width / 2
                    color: MColors.accent
                    border.width: Constants.borderWidthMedium
                    border.color: MColors.accentDark
                    antialiasing: true
                    
                    Icon {
                        anchors.centerIn: parent
                        name: "crosshair"
                        size: Constants.iconSizeMedium
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
                            console.log("Center on current location")
                        }
                    }
                    
                    Behavior on scale {
                        NumberAnimation { duration: 100 }
                    }
                }
            }
            
            // Location info bar
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Constants.spacingMedium
                height: Constants.touchTargetLarge
                radius: Constants.borderRadiusSharp
                color: MColors.surface
                border.width: Constants.borderWidthThin
                border.color: MColors.border
                antialiasing: Constants.enableAntialiasing
                visible: !showSearch
                
                Row {
                    anchors.fill: parent
                    anchors.margins: Constants.spacingMedium
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "map-pin"
                        size: Constants.iconSizeMedium
                        color: MColors.accent
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.spacing * 2 - Constants.iconSizeMedium * 2
                        spacing: Constants.spacingXSmall
                        
                        Text {
                            text: currentLocation
                            font.pixelSize: Constants.fontSizeMedium
                            font.weight: Font.DemiBold
                            color: MColors.text
                        }
                        
                        Text {
                            text: "Current location"
                            font.pixelSize: Constants.fontSizeSmall
                            color: MColors.textSecondary
                        }
                    }
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "navigation"
                        size: Constants.iconSizeMedium
                        color: MColors.accent
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
                        console.log("Start navigation")
                    }
                }
            }
        }
        
        // Search results overlay
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: Constants.touchTargetLarge + Constants.spacingMedium * 2
            anchors.leftMargin: Constants.spacingMedium
            anchors.rightMargin: Constants.spacingMedium
            height: Math.min(searchResults.length * (Constants.touchTargetLarge + Constants.spacingSmall) + Constants.spacingMedium, parent.height * 0.5)
            radius: Constants.borderRadiusSharp
            color: MColors.surface
            border.width: Constants.borderWidthMedium
            border.color: MColors.border
            antialiasing: Constants.enableAntialiasing
            visible: showSearch
            
            ListView {
                anchors.fill: parent
                anchors.margins: Constants.spacingMedium
                spacing: Constants.spacingSmall
                clip: true
                
                model: searchResults
                
                delegate: Rectangle {
                    width: ListView.view.width
                    height: Constants.touchTargetLarge
                    color: MColors.background
                    radius: Constants.borderRadiusSharp
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
                    Row {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingMedium
                        spacing: Constants.spacingMedium
                        
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: modelData.type === "cafe" ? "coffee" :
                                  modelData.type === "park" ? "tree-pine" :
                                  modelData.type === "museum" ? "landmark" : "map-pin"
                            size: Constants.iconSizeMedium
                            color: MColors.accent
                        }
                        
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - parent.spacing * 2 - Constants.iconSizeMedium * 2
                            spacing: Constants.spacingXSmall
                            
                            Text {
                                width: parent.width
                                text: modelData.name
                                font.pixelSize: Constants.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: MColors.text
                                elide: Text.ElideRight
                            }
                            
                            Row {
                                spacing: Constants.spacingSmall
                                
                                Text {
                                    text: modelData.address
                                    font.pixelSize: Constants.fontSizeSmall
                                    color: MColors.textSecondary
                                }
                                
                                Text {
                                    text: "•"
                                    font.pixelSize: Constants.fontSizeSmall
                                    color: MColors.textSecondary
                                }
                                
                                Text {
                                    text: modelData.distance
                                    font.pixelSize: Constants.fontSizeSmall
                                    color: MColors.textSecondary
                                }
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
                            parent.color = MColors.surface
                            HapticService.light()
                        }
                        onReleased: {
                            parent.color = MColors.background
                        }
                        onCanceled: {
                            parent.color = MColors.background
                        }
                        onClicked: {
                            console.log("Navigate to:", modelData.name)
                            showSearch = false
                            searchInput.text = ""
                        }
                    }
                }
            }
        }
    }
}
