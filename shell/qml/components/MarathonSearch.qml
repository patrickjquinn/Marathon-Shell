import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Item {
    id: searchOverlay
    
    property bool active: false
    property real pullProgress: 0.0  // 0.0 to 1.0, for pull-to-reveal animation
    property string searchQuery: ""
    property var searchResults: []
    
    signal closed()
    signal resultSelected(var result)
    
    visible: opacity > 0.01
    enabled: opacity > 0.01  // Block interactions whenever visible
    
    // Opacity: active = full opacity, OR follows pullProgress during gesture
    opacity: active ? 1.0 : Math.max(0.0, pullProgress)
    
    // Smooth fade-out when search closes or progress resets
    Behavior on opacity {
        enabled: !active
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    
    // Full-screen mouse blocker when visible at any opacity
    // Excludes nav bar area to allow swipe-up-to-close gesture
    MouseArea {
        anchors.fill: parent
        anchors.bottomMargin: Constants.bottomBarHeight
        enabled: searchOverlay.opacity > 0.01 && !searchOverlay.active
        onClicked: {
            // Clicking on overlay when partially visible dismisses it
            searchOverlay.pullProgress = 0.0
        }
    }
    
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.95)
    }
    
    Column {
        anchors.fill: parent
        anchors.topMargin: Constants.safeAreaTop + 8
        anchors.leftMargin: Constants.spacingLarge
        anchors.rightMargin: Constants.spacingLarge
        anchors.bottomMargin: Constants.safeAreaBottom + 20
        spacing: Constants.spacingMedium
        z: 10
        
        Item {
            width: parent.width
            height: 56
            
            Rectangle {
                id: searchBarContainer
                anchors.fill: parent
                color: MColors.surface
                radius: Constants.borderRadiusSharp
                border.width: searchInput.activeFocus ? Constants.borderWidthMedium : Constants.borderWidthThin
                border.color: searchInput.activeFocus ? MColors.accentBright : MColors.borderOuter
                antialiasing: Constants.enableAntialiasing
                
                Behavior on border.color {
                    ColorAnimation { duration: 200 }
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: Constants.iconSizeMedium
                        color: searchInput.activeFocus ? MColors.accentBright : MColors.textSecondary
                        
                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }
                    }
                    
                    TextInput {
                        id: searchInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80
                        color: MColors.text
                        font.pixelSize: MTypography.sizeLarge
                        font.family: MTypography.fontFamily
                        selectionColor: MColors.accentBright
                        selectedTextColor: MColors.text
                        
                        Keys.onEscapePressed: searchOverlay.close()
                        Keys.onDownPressed: resultsList.forceActiveFocus()
                        
                        onTextChanged: {
                            searchOverlay.searchQuery = text
                            performSearch()
                        }
                        
                        Text {
                            anchors.fill: parent
                            text: "Search apps, settings..."
                            color: MColors.textSecondary
                            font: parent.font
                            visible: !searchInput.text && !searchInput.activeFocus
                        }
                    }
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "x"
                        size: Constants.iconSizeSmall
                        color: MColors.textSecondary
                        visible: searchInput.text.length > 0
                        
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: {
                                searchInput.text = ""
                                searchInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }
        
        ListView {
            id: resultsList
            width: parent.width
            height: parent.height - 76
            clip: true
            spacing: Constants.spacingSmall
            model: searchOverlay.searchResults
            interactive: true
            boundsBehavior: Flickable.StopAtBounds
            
            Keys.onUpPressed: {
                if (currentIndex === 0) {
                    searchInput.forceActiveFocus()
                } else {
                    decrementCurrentIndex()
                }
            }
            Keys.onReturnPressed: {
                if (currentItem) {
                    var result = searchOverlay.searchResults[currentIndex]
                    selectResult(result)
                }
            }
            Keys.onEscapePressed: searchOverlay.close()
            
            delegate: Rectangle {
                width: resultsList.width
                height: Constants.appIconSize
                color: resultMouseArea.pressed ? MColors.surface2 : 
                       (resultsList.currentIndex === index ? MColors.surface1 : "transparent")
                radius: Constants.borderRadiusSharp
                antialiasing: Constants.enableAntialiasing
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: Constants.spacingMedium
                    
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48
                        height: 48
                        radius: modelData.type === "app" ? Constants.borderRadiusSharp : 24
                        color: MColors.surface1
                        antialiasing: Constants.enableAntialiasing
                        
                        Image {
                            anchors.centerIn: parent
                            width: modelData.type === "app" ? 40 : 24
                            height: modelData.type === "app" ? 40 : 24
                            source: modelData.icon
                            smooth: true
                            antialiasing: true
                        }
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 76
                        spacing: 4
                        
                        Text {
                            width: parent.width
                            text: modelData.title
                            color: MColors.text
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightDemiBold
                            font.family: MTypography.fontFamily
                            elide: Text.ElideRight
                        }
                        
                        Row {
                            spacing: Constants.spacingSmall
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: typeText.width + 12
                                height: Constants.navBarHeight
                                radius: Constants.borderRadiusSharp
                                color: {
                                    if (modelData.type === "app") return MColors.surface2
                                    if (modelData.type === "deeplink") return Qt.rgba(139/255, 92/255, 246/255, 0.15)
                                    return Qt.rgba(59/255, 130/255, 246/255, 0.15)
                                }
                                antialiasing: Constants.enableAntialiasing
                                
                                Text {
                                    id: typeText
                                    anchors.centerIn: parent
                                    text: {
                                        if (modelData.type === "app") return "App"
                                        if (modelData.type === "deeplink") return "Page"
                                        return "Setting"
                                    }
                                    color: {
                                        if (modelData.type === "app") return MColors.accentBright
                                        if (modelData.type === "deeplink") return Qt.rgba(167/255, 139/255, 250/255, 1.0)
                                        return Qt.rgba(96/255, 165/255, 250/255, 1.0)
                                    }
                                    font.pixelSize: MTypography.sizeSmall
                                    font.weight: MTypography.weightMedium
                                    font.family: MTypography.fontFamily
                                }
                            }
                            
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.subtitle
                                color: MColors.textSecondary
                                font.pixelSize: MTypography.sizeSmall
                                font.family: MTypography.fontFamily
                            }
                        }
                    }
                }
                
                MouseArea {
                    id: resultMouseArea
                    anchors.fill: parent
                    onClicked: {
                        resultsList.currentIndex = index
                        selectResult(modelData)
                    }
                }
            }
            
            Text {
                anchors.centerIn: parent
                text: searchInput.text.length === 0 ? 
                      "Start typing to search" : 
                      "No results found"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                visible: resultsList.count === 0
            }
        }
    }
    
    function open() {
        searchInput.forceActiveFocus()
        Logger.info("Search", "Search overlay opened - input focused")
    }
    
    function close() {
        searchInput.text = ""
        searchResults = []
        closed()
        Logger.info("Search", "Search overlay closed")
    }
    
    function appendToSearch(text) {
        searchInput.text += text
        searchInput.forceActiveFocus()
    }
    
    function performSearch() {
        if (searchQuery.trim().length === 0) {
            searchResults = []
            return
        }
        
        var results = UnifiedSearchService.search(searchQuery)
        searchResults = results.slice(0, 20)
        
        Logger.info("Search", "Search performed: '" + searchQuery + "' - " + searchResults.length + " results")
    }
    
    function selectResult(result) {
        // Prevent double execution
        if (searchOverlay.opacity < 1.0 || !active) {
            return
        }
        
        Logger.info("Search", "Result selected: " + result.title)
        UnifiedSearchService.addToRecentSearches(searchQuery)
        
        // Close first to prevent double-tap through
        close()
        
        // Execute after a brief delay to ensure search is closed
        Qt.callLater(function() {
            UnifiedSearchService.executeSearchResult(result)
            resultSelected(result)
        })
    }
    
    onActiveChanged: {
        if (active) {
            Logger.info("Search", "Search became active - focusing input")
            Qt.callLater(function() {
                searchInput.forceActiveFocus()
            })
        } else {
            searchInput.text = ""
            searchResults = []
            Logger.info("Search", "Search became inactive - emitting closed signal")
            closed()
        }
    }
}

