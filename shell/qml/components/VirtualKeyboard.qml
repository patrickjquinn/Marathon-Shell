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
    
    // When external code changes active, show/hide keyboard via Qt.inputMethod
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
    
    // Monitor Qt.inputMethod.visible to sync back (read-only, no crash!)
    Connections {
        target: Qt.inputMethod
        
        function onVisibleChanged() {
            var isVisible = Qt.inputMethod.visible
            Logger.info("VirtualKeyboard", "Qt.inputMethod.visible changed to: " + isVisible)
            if (keyboardContainer.active !== isVisible) {
                keyboardContainer.active = isVisible
            }
        }
    }
    
    InputPanel {
        id: inputPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        
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
        visible: inputPanel.visible
    }
}

