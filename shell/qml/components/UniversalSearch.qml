import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: searchOverlay
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.98)
    visible: UIStore.searchOpen
    z: 2800
    opacity: visible ? 1 : 0
    
    Behavior on opacity {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    
    property string searchQuery: ""
    property var searchResults: []
    
    function performSearch(query) {
        searchQuery = query
        var results = []
        
        if (query.length === 0) {
            searchResults = []
            return
        }
        
        var lowerQuery = query.toLowerCase()
        
        for (var i = 0; i < AppStore.apps.length; i++) {
            var app = AppStore.apps[i]
            if (app.name.toLowerCase().includes(lowerQuery)) {
                results.push({
                    type: "app",
                    title: app.name,
                    subtitle: "Application",
                    icon: app.icon,
                    data: app
                })
            }
        }
        
        var settingsItems = [
            {name: "Wi-Fi", icon: "wifi"},
            {name: "Bluetooth", icon: "bluetooth"},
            {name: "Display", icon: "sun"},
            {name: "Sound", icon: "volume-2"},
            {name: "Network", icon: "globe"},
            {name: "Battery", icon: "battery"},
            {name: "Storage", icon: "hard-drive"},
            {name: "Security", icon: "lock"}
        ]
        
        for (var j = 0; j < settingsItems.length; j++) {
            if (settingsItems[j].name.toLowerCase().includes(lowerQuery)) {
                results.push({
                    type: "setting",
                    title: settingsItems[j].name,
                    subtitle: "Settings",
                    icon: settingsItems[j].icon,
                    data: settingsItems[j]
                })
            }
        }
        
        searchResults = results
    }
    
    MouseArea {
        anchors.fill: parent
        onClicked: UIStore.closeSearch()
    }
    
    Column {
        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight + 24
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 16
        
        Rectangle {
            width: parent.width
            height: 60
            radius: 4
            color: Qt.rgba(255, 255, 255, 0.08)
            border.width: 1
            border.color: searchInput.activeFocus ? Qt.rgba(20, 184, 166, 0.8) : Qt.rgba(255, 255, 255, 0.15)
            layer.enabled: true
            
            Behavior on border.color {
                ColorAnimation { duration: 150 }
            }
            
            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                
                Icon {
                    name: "search"
                    size: 24
                    color: Colors.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                TextInput {
                    id: searchInput
                    width: parent.width - 48
                    anchors.verticalCenter: parent.verticalCenter
                    color: Colors.text
                    font.pixelSize: Typography.sizeBody
                    font.family: Typography.fontFamily
                    selectionColor: Colors.accent
                    selectedTextColor: Colors.text
                    clip: true
                    
                    onTextChanged: {
                        performSearch(text)
                    }
                    
                    Text {
                        visible: parent.text.length === 0
                        text: "Search apps, settings..."
                        color: Colors.textTertiary
                        font: parent.font
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Component.onCompleted: {
                        if (searchOverlay.visible) {
                            forceActiveFocus()
                        }
                    }
                }
            }
        }
        
        ListView {
            width: parent.width
            height: parent.height - 76
            clip: true
            spacing: 0
            visible: searchResults.length > 0
            
            model: searchResults
            
            delegate: Rectangle {
                width: ListView.view.width
                height: 72
                color: "transparent"
                
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 4
                    color: Qt.rgba(255, 255, 255, 0.03)
                    opacity: resultMouseArea.pressed ? 1 : 0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 16
                    
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 4
                        color: Qt.rgba(255, 255, 255, 0.05)
                        border.width: 1
                        border.color: Qt.rgba(255, 255, 255, 0.08)
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Icon {
                            name: modelData.icon
                            size: 32
                            color: Colors.text
                            anchors.centerIn: parent
                        }
                    }
                    
                    Column {
                        width: parent.width - 76
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        
                        Text {
                            text: modelData.title
                            color: Colors.text
                            font.pixelSize: Typography.sizeBody
                            font.weight: Font.DemiBold
                            font.family: Typography.fontFamily
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        
                        Text {
                            text: modelData.subtitle
                            color: Colors.textSecondary
                            font.pixelSize: Typography.sizeSmall
                            font.family: Typography.fontFamily
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                }
                
                MouseArea {
                    id: resultMouseArea
                    anchors.fill: parent
                    onClicked: {
                        Logger.info("UniversalSearch", "Selected: " + modelData.title)
                        if (modelData.type === "app") {
                            AppStore.launchApp(modelData.data.id)
                            UIStore.openApp(modelData.data.id, modelData.data.name, modelData.data.icon)
                        } else if (modelData.type === "setting") {
                            UIStore.openApp("settings", "Settings", "qrc:/images/settings.svg")
                        }
                        UIStore.closeSearch()
                    }
                }
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Qt.rgba(255, 255, 255, 0.05)
                }
            }
        }
        
        Text {
            visible: searchQuery.length > 0 && searchResults.length === 0
            text: "No results found"
            color: Colors.textSecondary
            font.pixelSize: Typography.sizeBody
            font.family: Typography.fontFamily
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
    
    onVisibleChanged: {
        if (visible) {
            searchInput.text = ""
            searchInput.forceActiveFocus()
        }
    }
}

