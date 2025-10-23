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
    height: parent ? parent.height : 0  // Fill parent so InputPanel can anchor
    z: Constants.zIndexKeyboard
    
    // Debug our active state changes
    onActiveChanged: {
        Logger.info("VirtualKeyboard", "keyboardContainer.active changed to: " + active)
    }
    
    // InputPanel - bind active property directly to our state!
    // This is the official Qt way per documentation
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom  // Anchor to direct parent (keyboardContainer)
        // CRITICAL: Directly bind active to our state (DON'T break this binding!)
        active: keyboardContainer.active
        
        onActiveChanged: {
            Logger.info("VirtualKeyboard", "InputPanel.active changed to: " + active)
        }
        
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created. Initial active: " + active)
            // DON'T set inputPanel.active here - it breaks the binding!
            // Just ensure Qt.inputMethod is hidden
            Qt.inputMethod.hide()
        }
    }
}

