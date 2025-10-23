import QtQuick
import QtQuick.VirtualKeyboard
import MarathonOS.Shell

Item {
    id: keyboardContainer
    
    // Expose properties for external control
    property bool keyboardAvailable: true
    
    // IMPORTANT: Read-only! We READ inputPanel.active, we DON'T control it!
    // InputPanel manages its own active state based on Qt.inputMethod
    readonly property bool active: inputPanel.active
    
    // Proxy for external code (backward compatibility)
    readonly property QtObject keyboard: QtObject {
        readonly property bool active: inputPanel.active
    }
    
    // CRITICAL: Only occupy space when active! Otherwise it blocks all clicks!
    anchors.left: parent ? parent.left : undefined
    anchors.right: parent ? parent.right : undefined
    anchors.bottom: parent ? parent.bottom : undefined
    height: inputPanel.height
    z: Constants.zIndexKeyboard
    
    // When keyboard is hidden, don't block mouse events
    enabled: inputPanel.active
    
    /*  Virtual Keyboard Input Panel
        
        Following the official Qt VirtualKeyboard example pattern:
        - InputPanel manages its own 'active' state based on Qt.inputMethod
        - We NEVER write to inputPanel.active (it breaks internal state management)
        - We use y-positioning with States to show/hide based on inputPanel.active
        - External code uses Qt.inputMethod.show()/hide() to control visibility
        
        See: https://github.com/qt/qtvirtualkeyboard/blob/dev/examples/virtualkeyboard/basic/Basic.qml
    */
    InputPanel {
        id: inputPanel
        z: 89
        x: 0
        width: parent.width
        y: yPositionWhenHidden
        
        property real yPositionWhenHidden: parent.height
        
        states: State {
            name: "visible"
            // READ inputPanel.active, don't WRITE to it!
            when: inputPanel.active
            PropertyChanges {
                target: inputPanel
                y: inputPanel.yPositionWhenHidden - inputPanel.height
            }
        }
        
        transitions: Transition {
            from: ""
            to: "visible"
            reversible: true
            NumberAnimation {
                properties: "y"
                duration: 250
                easing.type: Easing.InOutQuad
            }
        }
        
        Component.onCompleted: {
            Logger.info("VirtualKeyboard", "InputPanel created. Initial active: " + active)
            // Ensure keyboard starts hidden
            Qt.inputMethod.hide()
        }
        
        onActiveChanged: {
            Logger.info("VirtualKeyboard", "InputPanel.active changed to: " + active)
        }
    }
}

