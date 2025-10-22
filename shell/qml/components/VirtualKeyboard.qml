import QtQuick
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    // Expose keyboard as a property for easy access
    property alias keyboard: keyboard
    property bool keyboardAvailable: keyboard.status === Loader.Ready
    
    width: parent ? parent.width : 0
    height: keyboardAvailable && keyboard.item ? keyboard.item.height : 0
    y: parent ? parent.height - height : 0
    z: Constants.zIndexKeyboard
    visible: keyboardAvailable && keyboard.item && keyboard.item.active
    
    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }
    
    Loader {
        id: keyboard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: true  // Try to load on startup
        asynchronous: true
        
        source: "qrc:/qt-project.org/imports/QtQuick/VirtualKeyboard/InputPanel.qml"
        
        onStatusChanged: {
            if (status === Loader.Error) {
                Logger.warn("VirtualKeyboard", "Qt VirtualKeyboard module not available")
                Logger.info("VirtualKeyboard", "Install qt6-virtualkeyboard package or set QT_IM_MODULE=qtvirtualkeyboard")
            } else if (status === Loader.Ready) {
                Logger.info("VirtualKeyboard", "Qt VirtualKeyboard loaded successfully")
            }
        }
        
        onLoaded: {
            Logger.info("VirtualKeyboard", "InputPanel loaded, initial active state: " + (item ? item.active : "N/A"))
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

