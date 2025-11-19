import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonApp.Terminal

Item {
    id: root
    
    property alias title: terminalEngine.title
    property alias running: terminalEngine.running
    
    signal sessionFinished()
    
    function start() {
        terminalEngine.start()
    }
    
    function terminate() {
        terminalEngine.terminate()
    }
    
    TerminalEngine {
        id: terminalEngine
        
        onFinished: {
            root.sessionFinished()
        }
    }
    
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        
        // Output display
        Flickable {
            id: outputFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: terminalRenderer.width
            contentHeight: terminalRenderer.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            
            // Padding
            leftMargin: MSpacing.md
            rightMargin: MSpacing.md
            topMargin: MSpacing.md
            bottomMargin: MSpacing.md
            
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                active: outputFlickable.moving || outputFlickable.flicking
            }
            
            TerminalRenderer {
                id: terminalRenderer
                width: outputFlickable.width - (outputFlickable.leftMargin + outputFlickable.rightMargin)
                height: outputFlickable.height - (outputFlickable.topMargin + outputFlickable.bottomMargin)
                terminal: terminalEngine
                
                font.family: MTypography.fontFamilyMono
                font.pixelSize: 14
                
                textColor: MColors.text
                backgroundColor: "transparent"
                
                focus: true // Capture keyboard input
                
                onCharSizeChanged: updateTerminalSize()
                onWidthChanged: updateTerminalSize()
                onHeightChanged: updateTerminalSize()
                
                function updateTerminalSize() {
                    if (charWidth > 0 && charHeight > 0) {
                        var cols = Math.floor(width / charWidth)
                        var rows = Math.floor(height / charHeight)
                        if (cols > 0 && rows > 0) {
                            terminalEngine.resize(cols, rows)
                        }
                    }
                }
                
                // Handle keyboard input
                Keys.onPressed: (event) => {
                    var text = event.text
                    var key = event.key
                    var modifiers = event.modifiers
                    
                    // Handle special keys
                    if (key === Qt.Key_Backspace) {
                        terminalEngine.sendKey(key, "", modifiers)
                        event.accepted = true
                        return
                    }
                    
                    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
                        terminalEngine.sendKey(key, "", modifiers)
                        event.accepted = true
                        return
                    }
                    
                    if (key === Qt.Key_Up || key === Qt.Key_Down || key === Qt.Key_Left || key === Qt.Key_Right) {
                        terminalEngine.sendKey(key, "", modifiers)
                        event.accepted = true
                        return
                    }
                    
                    if (key === Qt.Key_Tab) {
                        terminalEngine.sendKey(key, "", modifiers)
                        event.accepted = true
                        return
                    }
                    
                    if (key === Qt.Key_Escape) {
                        terminalEngine.sendKey(key, "", modifiers)
                        event.accepted = true
                        return
                    }
                    
                    // Ctrl+C, etc.
                    if (modifiers & Qt.ControlModifier) {
                        if (key >= Qt.Key_A && key <= Qt.Key_Z) {
                             terminalEngine.sendKey(key, text, modifiers)
                             event.accepted = true
                             return
                        }
                    }
                    
                    // Normal text input
                    if (text.length > 0) {
                        terminalEngine.sendInput(text)
                        event.accepted = true
                    }
                }
                
                // Ensure focus is kept
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        terminalRenderer.forceActiveFocus()
                        Qt.inputMethod.show() // Show virtual keyboard on touch
                    }
                }
            }
        }
        
        // Virtual Key Row
        VirtualKeyRow {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            
            onKeyTriggered: (key, modifiers) => {
                terminalEngine.sendKey(key, "", modifiers)
            }
        }
    }
}
