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
    
    // Use y-positioning to show/hide, not visible property!
    // This allows InputPanel's dismiss button to work
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    y: 0
    z: Constants.zIndexKeyboard
    
    // Control keyboard via Qt.inputMethod (proper API)
    onActiveChanged: {
        Logger.info("VirtualKeyboard", "Active changed externally to: " + active)
        if (active) {
            Qt.inputMethod.show()
        } else {
            Qt.inputMethod.hide()
        }
    }
    
    // InputPanel - let it manage itself!
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        // Use y-positioning for show/hide animation
        y: inputPanel.active ? parent.height - inputPanel.height : parent.height
        
        Behavior on y {
            NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
        }
        
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created")
            // Force hide on startup
            Qt.inputMethod.hide()
        }
    }
}

