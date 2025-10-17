import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Item {
    id: root
    
    property Component sourceComponent: null
    property var appInstance: loader.item
    property string appId: ""
    property bool isActive: true
    
    signal loadError(string message)
    signal loadSuccess()
    
    Rectangle {
        id: errorContainer
        anchors.fill: parent
        color: MColors.background
        visible: false
        z: 100
        
        Column {
            anchors.centerIn: parent
            spacing: Constants.spacingLarge
            width: parent.width * 0.8
            
            Icon {
                name: "alert-triangle"
                size: Constants.iconSizeXLarge
                color: MColors.error
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Text {
                text: "App Crashed"
                font.pixelSize: Constants.fontSizeXLarge
                font.weight: Font.DemiBold
                color: MColors.text
                anchors.horizontalCenter: parent.horizontalCenter
            }
            
            Text {
                text: "The app encountered an error and stopped working."
                font.pixelSize: Constants.fontSizeMedium
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }
            
            Button {
                text: "Restart App"
                anchors.horizontalCenter: parent.horizontalCenter
                
                background: Rectangle {
                    color: parent.pressed ? MColors.accentDark : MColors.accent
                    radius: Constants.borderRadiusSmall
                    
                    Behavior on color {
                        ColorAnimation { duration: Constants.animationFast }
                    }
                }
                
                contentItem: Text {
                    text: parent.text
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.Medium
                    color: MColors.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: root.restart()
            }
        }
    }
    
    Loader {
        id: loader
        anchors.fill: parent
        active: root.isActive
        asynchronous: true
        sourceComponent: root.sourceComponent
        
        onStatusChanged: {
            if (status === Loader.Error) {
                console.error("SafeAppLoader: Failed to load app", root.appId)
                console.error("  Error string:", loader.sourceComponent)
                errorContainer.visible = true
                root.loadError("Failed to load component")
                
                if (root.appId) {
                    StateManager.saveAppState(root.appId, "crashed")
                }
            } else if (status === Loader.Ready) {
                errorContainer.visible = false
                root.loadSuccess()
            } else if (status === Loader.Loading) {
                errorContainer.visible = false
            }
        }
        
        onLoaded: {
            if (item) {
                console.log("SafeAppLoader: Successfully loaded app", root.appId)
            }
        }
    }
    
    function restart() {
        console.log("SafeAppLoader: Restarting app", root.appId)
        errorContainer.visible = false
        
        loader.active = false
        
        Qt.callLater(() => {
            loader.active = true
        })
    }
    
    function unload() {
        loader.active = false
    }
    
    function reload() {
        restart()
    }
}

