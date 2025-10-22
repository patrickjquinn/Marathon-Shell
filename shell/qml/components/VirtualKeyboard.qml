import QtQuick
import QtQuick.VirtualKeyboard
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    // Expose keyboard directly
    property alias keyboard: inputPanel
    property bool keyboardAvailable: true  // Always true since we import the module
    
    width: parent ? parent.width : 0
    height: inputPanel.active ? inputPanel.height : 0
    y: parent ? parent.height - height : 0
    z: Constants.zIndexKeyboard
    visible: inputPanel.active
    
    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }
    
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: false
        
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created, initial active: " + active)
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
        visible: inputPanel.active
    }
}

