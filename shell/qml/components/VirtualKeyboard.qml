import QtQuick
import QtQuick.VirtualKeyboard
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    // Expose properties for external control
    property bool keyboardAvailable: true
    property bool active: false
    
    // Proxy for external code - read-only
    readonly property QtObject keyboard: QtObject {
        property bool active: keyboardContainer.active
    }
    
    width: parent ? parent.width : 0
    // NEVER read inputPanel.visible! It causes crashes!
    // Use our own state tracking instead
    height: active ? 300 : 0  // Fixed height when shown
    y: parent ? parent.height - height : 0
    z: Constants.zIndexKeyboard
    visible: active
    
    // ONE-WAY CONTROL ONLY: We can show/hide, but DON'T observe dismiss!
    onActiveChanged: {
        Logger.info("VirtualKeyboard", "Active changed externally to: " + active)
        if (active) {
            Qt.inputMethod.show()
        } else {
            Qt.inputMethod.hide()
        }
    }
    
    Behavior on height {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }
    
    // NO CONNECTIONS! Don't observe InputPanel at all!
    
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: keyboardContainer.active
        
        // CRITICAL: Start hidden! Don't auto-show on creation!
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created, forcing hide")
            Qt.inputMethod.hide()
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

