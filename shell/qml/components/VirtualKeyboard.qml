import QtQuick
import QtQuick.VirtualKeyboard
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    // Expose properties for external control
    property bool keyboardAvailable: true
    property bool active: false
    readonly property real keyboardHeight: inputPanel.y
    
    // CRITICAL: Guard flag to prevent bidirectional binding loop
    property bool _syncInProgress: false
    
    // CRITICAL: Don't expose inputPanel directly, use controlled properties
    readonly property QtObject keyboard: QtObject {
        property bool active: keyboardContainer.active
    }
    
    width: parent ? parent.width : 0
    height: active ? inputPanel.height : 0
    y: parent ? parent.height - height : 0
    z: Constants.zIndexKeyboard
    visible: active
    
    // Sync our active property to InputPanel with safety checks
    onActiveChanged: {
        if (_syncInProgress) {
            return  // CRITICAL: Prevent loop when sync originated from InputPanel
        }
        
        Logger.info("VirtualKeyboard", "Container active changed to: " + active)
        _syncInProgress = true
        
        if (inputPanel) {
            inputPanel.active = active
        }
        
        _syncInProgress = false
    }
    
    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }
    
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: false
        
        // Sync InputPanel state back to container (when dismiss button clicked)
        onActiveChanged: {
            if (keyboardContainer._syncInProgress) {
                return  // CRITICAL: Prevent loop when sync originated from container
            }
            
            Logger.info("VirtualKeyboard", "InputPanel active changed to: " + active + " (dismiss button clicked?)")
            keyboardContainer._syncInProgress = true
            
            if (active !== keyboardContainer.active) {
                keyboardContainer.active = active
            }
            
            keyboardContainer._syncInProgress = false
        }
        
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created")
        }
        
        Component.onDestruction: {
            Logger.info("VirtualKeyboard", "InputPanel being destroyed")
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
        visible: keyboardContainer.active
    }
}

