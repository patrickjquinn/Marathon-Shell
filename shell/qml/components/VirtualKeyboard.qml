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
    height: inputPanel.visible ? inputPanel.height : 0
    y: parent ? parent.height - height : 0
    z: Constants.zIndexKeyboard
    visible: inputPanel.visible
    
    // ONE-WAY CONTROL ONLY: We can show/hide, but DON'T observe dismiss!
    // The user pressing InputPanel's dismiss button will hide it,
    // but we won't know about it. That's OK - it prevents crashes.
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
    
    // NO CONNECTIONS! Don't observe InputPanel state changes!
    // This prevents ALL crash scenarios related to dismiss button.
    
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created")
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
        visible: inputPanel.visible
    }
}

