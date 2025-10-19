import QtQuick
import QtQuick.Controls
import QtLocation
import QtPositioning
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

MApp {
    id: mapsApp
    appId: "maps"
    appName: "Maps"
    appIcon: "assets/icon.svg"
    
    property bool showSearch: false
    property var searchResults: []
    property bool isSearching: false
    property bool mapLoaded: false
    
    onAppLaunched: {
        loadTimer.start()
    }
    
    Timer {
        id: loadTimer
        interval: 100
        onTriggered: {
            mapLoaded = true
        }
    }
    
    PositionSource {
        id: positionSource
        active: mapLoaded
        updateInterval: 5000
        
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid && mapLoader.item) {
                mapLoader.item.center = position.coordinate
                Logger.info("Maps", "Position updated: " + position.coordinate)
            }
        }
        
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError) {
                Logger.warn("Maps", "Position source error (macOS stub mode)")
            }
        }
    }
    
    function searchLocation(query) {
        if (query.length === 0) {
            searchResults = []
            return
        }
        
        isSearching = true
        var xhr = new XMLHttpRequest()
        var url = "https://nominatim.openstreetmap.org/search?q=" + encodeURIComponent(query) + "&format=json&limit=5"
        
        xhr.open("GET", url)
        xhr.setRequestHeader("User-Agent", "MarathonOS/1.0")
        
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isSearching = false
                if (xhr.status === 200) {
                    try {
                        var results = JSON.parse(xhr.responseText)
                        searchResults = results.map(function(result) {
                            return {
                                name: result.display_name.split(',')[0],
                                address: result.display_name,
                                lat: parseFloat(result.lat),
                                lon: parseFloat(result.lon),
                                type: result.type
                            }
                        })
                        Logger.info("Maps", "Found " + searchResults.length + " results")
                    } catch (e) {
                        Logger.error("Maps", "Failed to parse search results: " + e)
                        searchResults = []
                    }
                } else {
                    Logger.error("Maps", "Search request failed: " + xhr.status)
                    searchResults = []
                }
            }
        }
        
        xhr.send()
    }
    
    function goToLocation(lat, lon) {
        if (mapLoader.item) {
            mapLoader.item.center = QtPositioning.coordinate(lat, lon)
            mapLoader.item.zoomLevel = 15
            showSearch = false
        }
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Loader {
            id: mapLoader
            anchors.fill: parent
            active: mapLoaded
            asynchronous: true
            
            sourceComponent: Map {
                id: map
                anchors.fill: parent
                
                plugin: Plugin {
                    name: "osm"
                }
                
                center: positionSource.position.valid ? positionSource.position.coordinate : QtPositioning.coordinate(37.7749, -122.4194)
                zoomLevel: 14
                
                // Gestures are enabled by default in Qt 6
                // gesture.enabled: true removed - not a valid property
                
                MapQuickItem {
                    id: userLocationMarker
                    coordinate: positionSource.position.valid ? positionSource.position.coordinate : map.center
                    anchorPoint.x: locationDot.width / 2
                    anchorPoint.y: locationDot.height / 2
                    
                    sourceItem: Rectangle {
                        id: locationDot
                        width: Constants.spacingLarge
                        height: Constants.spacingLarge
                        radius: width / 2
                        color: MColors.accent
                        border.width: Constants.borderWidthThick
                        border.color: "white"
                        
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.4
                            height: parent.height * 0.4
                            radius: width / 2
                            color: "white"
                        }
                    }
                }
            }
        }
        
        Rectangle {
            anchors.fill: parent
            color: MColors.background
            visible: !mapLoaded
            
            Column {
                anchors.centerIn: parent
                spacing: Constants.spacingLarge
                
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "map"
                    size: Constants.iconSizeXLarge * 2
                    color: MColors.accent
                    
                    RotationAnimation on rotation {
                        running: !mapLoaded
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 2000
                    }
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Loading map..."
                    font.pixelSize: Constants.fontSizeLarge
                    color: MColors.textSecondary
                }
            }
        }
        
        Rectangle {
            id: searchBar
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
            z: 100
            
            Row {
                anchors.fill: parent
                anchors.margins: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: isSearching ? "loader" : "search"
                    size: Constants.iconSizeMedium
                    color: MColors.textSecondary
                    
                    RotationAnimation on rotation {
                        running: isSearching
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1000
                    }
                }
                
                TextInput {
                    id: searchInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.spacing * 3 - Constants.iconSizeMedium * 2
                    font.pixelSize: Constants.fontSizeMedium
                    color: MColors.text
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    
                    onTextChanged: {
                        showSearch = text.length > 0
                        if (text.length > 2) {
                            searchTimer.restart()
                        }
                    }
                    
                    Text {
                        anchors.fill: parent
                        text: "Search for places..."
                        font.pixelSize: Constants.fontSizeMedium
                        color: MColors.textTertiary
                        verticalAlignment: Text.AlignVCenter
                        visible: !searchInput.text && !searchInput.activeFocus
                    }
                }
                
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "x"
                    size: Constants.iconSizeMedium
                    color: MColors.textSecondary
                    visible: searchInput.text.length > 0
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            searchInput.text = ""
                            showSearch = false
                        }
                    }
                }
            }
        }
        
        Timer {
            id: searchTimer
            interval: 500
            onTriggered: {
                searchLocation(searchInput.text)
            }
        }
        
        Rectangle {
            id: searchResultsPanel
            anchors.top: searchBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Constants.spacingMedium
            anchors.topMargin: Constants.spacingSmall
            height: Math.min(searchResultsList.contentHeight + Constants.spacingMedium * 2, parent.height * 0.5)
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthMedium
            border.color: MColors.border
            visible: showSearch && searchResults.length > 0
            z: 99
            
            ListView {
                id: searchResultsList
                anchors.fill: parent
                anchors.margins: Constants.spacingSmall
                clip: true
                
                model: searchResults
                
                delegate: Rectangle {
                    width: searchResultsList.width
                    height: Constants.touchTargetLarge + Constants.spacingSmall
                    color: "transparent"
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingXSmall
                        color: MColors.surface
                        radius: Constants.borderRadiusSharp
                        border.width: Constants.borderWidthThin
                        border.color: MColors.border
                        
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
                                width: parent.width - parent.children[0].width - parent.spacing
                                spacing: Constants.spacingXSmall
                                
                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    font.pixelSize: Constants.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: MColors.text
                                    elide: Text.ElideRight
                                }
                                
                                Text {
                                    width: parent.width
                                    text: modelData.address
                                    font.pixelSize: Constants.fontSizeSmall
                                    color: MColors.textSecondary
                                    elide: Text.ElideRight
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
                                Logger.info("Maps", "Selected: " + modelData.name)
                                goToLocation(modelData.lat, modelData.lon)
                            }
                        }
                    }
                }
            }
        }
        
        Column {
            anchors.right: parent.right
            anchors.bottom: locateButton.top
            anchors.margins: Constants.spacingLarge
            anchors.bottomMargin: Constants.spacingMedium
            spacing: Constants.spacingMedium
            z: 100
            
            Rectangle {
                width: Constants.touchTargetLarge
                height: Constants.touchTargetLarge
                radius: Constants.borderRadiusSharp
                color: MColors.surface
                border.width: Constants.borderWidthMedium
                border.color: MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Icon {
                    anchors.centerIn: parent
                    name: "plus"
                    size: Constants.iconSizeLarge
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        parent.scale = 0.9
                        HapticService.light()
                    }
                    onReleased: {
                        parent.scale = 1.0
                    }
                    onCanceled: {
                        parent.scale = 1.0
                    }
                    onClicked: {
                        if (mapLoader.item) {
                            mapLoader.item.zoomLevel = Math.min(mapLoader.item.zoomLevel + 1, mapLoader.item.maximumZoomLevel)
                        }
                    }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 100 }
                }
            }
            
            Rectangle {
                width: Constants.touchTargetLarge
                height: Constants.touchTargetLarge
                radius: Constants.borderRadiusSharp
                color: MColors.surface
                border.width: Constants.borderWidthMedium
                border.color: MColors.border
                antialiasing: Constants.enableAntialiasing
                
                Icon {
                    anchors.centerIn: parent
                    name: "minus"
                    size: Constants.iconSizeLarge
                    color: MColors.text
                }
                
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        parent.scale = 0.9
                        HapticService.light()
                    }
                    onReleased: {
                        parent.scale = 1.0
                    }
                    onCanceled: {
                        parent.scale = 1.0
                    }
                    onClicked: {
                        if (mapLoader.item) {
                            mapLoader.item.zoomLevel = Math.max(mapLoader.item.zoomLevel - 1, mapLoader.item.minimumZoomLevel)
                        }
                    }
                }
                
                Behavior on scale {
                    NumberAnimation { duration: 100 }
                }
            }
        }
        
        Rectangle {
            id: locateButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Constants.spacingLarge
            width: Constants.touchTargetLarge
            height: Constants.touchTargetLarge
            radius: Constants.touchTargetLarge / 2
            color: MColors.accent
            border.width: Constants.borderWidthThick
            border.color: MColors.accentDark
            antialiasing: true
            z: 100
            
            Icon {
                anchors.centerIn: parent
                name: "navigation"
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
                    if (positionSource.position.valid && mapLoader.item) {
                        mapLoader.item.center = positionSource.position.coordinate
                        mapLoader.item.zoomLevel = 15
                        Logger.info("Maps", "Centered on current location")
                    } else {
                        Logger.warn("Maps", "Position not available")
                    }
                }
            }
            
            Behavior on scale {
                NumberAnimation { duration: 100 }
            }
        }
    }
}
