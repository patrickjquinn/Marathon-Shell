import QtQuick
import QtQuick.VirtualKeyboard
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    // Expose properties for external control
    property bool keyboardAvailable: true
    property bool active: false
    readonly property real keyboardHeight: inputPanel.y
    
    // CRITICAL: Don't expose inputPanel directly, use controlled properties
    readonly property QtObject keyboard: QtObject {
        property bool active: keyboardContainer.active
    }
    
    width: parent ? parent.width : 0
    height: active ? inputPanel.height : 0
    y: parent ? parent.height - height : 0
    z: Constants.zIndexKeyboard
    visible: active
    
    // Guard flag to prevent bidirectional binding loops
    property bool updatingFromInputPanel: false
    
    // Sync our active property to InputPanel with safety checks
    onActiveChanged: {
        if (updatingFromInputPanel) {
            return  // Don't write back if we're syncing FROM InputPanel
        }
        
        Logger.info("VirtualKeyboard", "Active changed externally to: " + active)
        if (inputPanel) {
            // Defer the update to avoid crash during InputPanel destruction
            Qt.callLater(function() {
                if (inputPanel) {
                    inputPanel.active = active
                }
            })
        }
    }
    
    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }
    
    // Use Connections to safely monitor InputPanel without bidirectional binding
    Connections {
        target: inputPanel
        
        function onActiveChanged() {
            if (inputPanel && inputPanel.active !== keyboardContainer.active) {
                Logger.info("VirtualKeyboard", "InputPanel dismissed via button, syncing to: " + inputPanel.active)
                updatingFromInputPanel = true
                keyboardContainer.active = inputPanel.active
                updatingFromInputPanel = false
            }
        }
    }
    
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        active: false
        
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

