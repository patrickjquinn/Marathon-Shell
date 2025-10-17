import QtQuick
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    width: parent ? parent.width : 0
    height: 0
    y: parent ? parent.height : 0
    z: Constants.zIndexKeyboard
    visible: false
    
    Loader {
        id: keyboard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: false
        
        source: "qrc:/qt-project.org/imports/QtQuick/VirtualKeyboard/InputPanel.qml"
        
        onStatusChanged: {
            if (status === Loader.Error) {
                console.warn("[VirtualKeyboard] Qt VirtualKeyboard not available - using fallback")
            } else if (status === Loader.Ready) {
                console.log("[VirtualKeyboard] Qt VirtualKeyboard loaded successfully")
                keyboardContainer.visible = true
            }
        }
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -4
        color: Qt.rgba(15, 15, 15, 0.98)
        radius: 0
        border.width: 1
        border.color: Qt.rgba(255, 255, 255, 0.12)
        z: -1
        visible: keyboard.status === Loader.Ready
    }
}

