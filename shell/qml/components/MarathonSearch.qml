import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Item {
    id: searchOverlay
    
    property bool active: false
    property string searchQuery: ""
    property var searchResults: []
    
    signal closed()
    signal resultSelected(var result)
    
    visible: opacity > 0
    opacity: active ? 1.0 : 0.0
    
    Behavior on opacity {
        NumberAnimation { 
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.95)
        
        MouseArea {
            anchors.fill: parent
            onClicked: searchOverlay.close()
        }
    }
    
    Column {
        anchors.fill: parent
        anchors.topMargin: Constants.safeAreaTop + 16
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.bottomMargin: Constants.safeAreaBottom + 16
        spacing: 16
        
        Item {
            width: parent.width
            height: 56
            
            Rectangle {
                id: searchBarContainer
                anchors.fill: parent
                color: Colors.surface
                radius: MRadius.md
                border.width: searchInput.activeFocus ? 2 : 1
                border.color: searchInput.activeFocus ? Colors.accent : Colors.border
                
                Behavior on border.color {
                    ColorAnimation { duration: 200 }
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: 24
                        color: searchInput.activeFocus ? Colors.accent : Colors.textSecondary
                        
                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }
                    }
                    
                    TextInput {
                        id: searchInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 80
                        color: Colors.text
                        font.pixelSize: MTypography.sizeLarge
                        font.family: MTypography.fontFamily
                        selectionColor: Colors.accent
                        selectedTextColor: Colors.text
                        
                        Keys.onEscapePressed: searchOverlay.close()
                        Keys.onDownPressed: resultsList.forceActiveFocus()
                        
                        onTextChanged: {
                            searchOverlay.searchQuery = text
                            performSearch()
                        }
                        
                        Text {
                            anchors.fill: parent
                            text: "Search apps, settings..."
                            color: Colors.textTertiary
                            font: parent.font
                            visible: !searchInput.text && !searchInput.activeFocus
                        }
                    }
                    
                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "x"
                        size: 20
                        color: Colors.textSecondary
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
            height: parent.height - 72
            clip: true
            spacing: 8
            model: searchOverlay.searchResults
            
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
                height: 72
                color: resultMouseArea.pressed ? Qt.rgba(255, 255, 255, 0.08) : 
                       (resultsList.currentIndex === index ? Qt.rgba(255, 255, 255, 0.04) : "transparent")
                radius: MRadius.sm
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 16
                    
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 48
                        height: 48
                        radius: modelData.type === "app" ? MRadius.md : 24
                        color: Qt.rgba(255, 255, 255, 0.04)
                        
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
                            color: Colors.text
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightDemiBold
                            font.family: MTypography.fontFamily
                            elide: Text.ElideRight
                        }
                        
                        Row {
                            spacing: 8
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: typeText.width + 12
                                height: 20
                                radius: 4
                                color: modelData.type === "app" ? 
                                       Qt.rgba(20/255, 184/255, 166/255, 0.15) : 
                                       Qt.rgba(59/255, 130/255, 246/255, 0.15)
                                
                                Text {
                                    id: typeText
                                    anchors.centerIn: parent
                                    text: modelData.type === "app" ? "App" : "Setting"
                                    color: modelData.type === "app" ? Colors.accent : Qt.rgba(96/255, 165/255, 250/255, 1.0)
                                    font.pixelSize: MTypography.sizeSmall
                                    font.weight: MTypography.weightMedium
                                    font.family: MTypography.fontFamily
                                }
                            }
                            
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.subtitle
                                color: Colors.textSecondary
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
                color: Colors.textTertiary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                visible: resultsList.count === 0
            }
        }
    }
    
    function open() {
        active = true
        searchInput.forceActiveFocus()
        Logger.info("Search", "Search overlay opened")
    }
    
    function close() {
        active = false
        searchInput.text = ""
        searchResults = []
        closed()
        Logger.info("Search", "Search overlay closed")
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
        Logger.info("Search", "Result selected: " + result.title)
        UnifiedSearchService.addToRecentSearches(searchQuery)
        UnifiedSearchService.executeSearchResult(result)
        resultSelected(result)
        close()
    }
    
    onActiveChanged: {
        if (!active) {
            searchInput.text = ""
            searchResults = []
        }
    }
}

