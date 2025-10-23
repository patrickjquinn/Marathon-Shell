import QtQuick
import QtQuick.VirtualKeyboard
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    // Expose properties for external control
    property bool keyboardAvailable: true
    property bool active: false
    
    // Proxy for external code
    readonly property QtObject keyboard: QtObject {
        property bool active: keyboardContainer.active
    }
    
    width: parent ? parent.width : 0
    height: 0  // No height, InputPanel manages itself
    z: Constants.zIndexKeyboard
    
    // InputPanel - bind active property directly to our state!
    // This is the official Qt way per documentation
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.parent.bottom
        // CRITICAL: Directly bind active to our state
        active: keyboardContainer.active
        
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created with active binding")
        }
    }
}

