// Marathon Virtual Keyboard - QWERTY Layout
// BlackBerry 10-style QWERTY keyboard layout
import QtQuick
import MarathonOS.Shell
import "../UI"
import "../Data"

Item {
    id: layout
    
    // Properties
    property bool shifted: false
    property bool capsLock: false
    
    // Expose Column's implicit height
    implicitHeight: layoutColumn.implicitHeight
    
    // Signals
    signal keyClicked(string text)
    signal backspaceClicked()
    signal enterClicked()
    signal shiftClicked()
    signal spaceClicked()
    signal layoutSwitchClicked(string layout)
    signal dismissClicked()
    
    // Key definitions with alternates
    readonly property var row1Keys: [
        {char: "q", alts: []},
        {char: "w", alts: []},
        {char: "e", alts: ["è", "é", "ê", "ë", "ē"]},
        {char: "r", alts: []},
        {char: "t", alts: ["þ"]},
        {char: "y", alts: ["ý", "ÿ"]},
        {char: "u", alts: ["ù", "ú", "û", "ü", "ū"]},
        {char: "i", alts: ["ì", "í", "î", "ï", "ī"]},
        {char: "o", alts: ["ò", "ó", "ô", "õ", "ö", "ø", "ō"]},
        {char: "p", alts: []}
    ]
    readonly property var row2Keys: [
        {char: "a", alts: ["à", "á", "â", "ã", "ä", "å", "æ", "ā"]},
        {char: "s", alts: ["ś", "š", "ş", "ß"]},
        {char: "d", alts: ["ð"]},
        {char: "f", alts: []},
        {char: "g", alts: []},
        {char: "h", alts: []},
        {char: "j", alts: []},
        {char: "k", alts: []},
        {char: "l", alts: ["ł"]}
    ]
    readonly property var row3Keys: [
        {char: "z", alts: ["ź", "ż", "ž"]},
        {char: "x", alts: []},
        {char: "c", alts: ["ç", "ć", "č"]},
        {char: "v", alts: []},
        {char: "b", alts: []},
        {char: "n", alts: ["ñ", "ń"]},
        {char: "m", alts: []}
    ]
    
    Column {
        id: layoutColumn
        width: parent.width
        spacing: 0
        
        // Row 1: Q W E R T Y U I O P
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            readonly property real keyWidth: (width - spacing * 9) / 10
            
            Repeater {
                model: row1Keys
                
                Key {
                    width: parent.keyWidth
                    text: modelData.char
                    displayText: layout.shifted || layout.capsLock ? modelData.char.toUpperCase() : modelData.char
                    alternateChars: modelData.alts
                    
                    onClicked: {
                        layout.keyClicked(displayText)
                    }
                    
                    onAlternateSelected: function(character) {
                        layout.keyClicked(character)
                    }
                }
            }
        }
        
        // Separator line between Row 1 and Row 2
        Rectangle {
            width: parent.width
            height: Math.round(2 * Constants.scaleFactor)
            color: "#666666"  // BRIGHT grey line - very visible
            opacity: 1.0
        }
        
        // Row 2: A S D F G H J K L
        Row {
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            readonly property real keyWidth: (width - spacing * 8) / 9
            
            Repeater {
                model: row2Keys
                
                Key {
                    width: parent.keyWidth
                    text: modelData.char
                    displayText: layout.shifted || layout.capsLock ? modelData.char.toUpperCase() : modelData.char
                    alternateChars: modelData.alts
                    
                    onClicked: {
                        layout.keyClicked(displayText)
                    }
                    
                    onAlternateSelected: function(character) {
                        layout.keyClicked(character)
                    }
                }
            }
        }
        
        // Separator line between Row 2 and Row 3
        Rectangle {
            width: parent.width
            height: Math.round(2 * Constants.scaleFactor)
            color: "#666666"
            opacity: 1.0
        }
        
        // Row 3: Shift Z X C V B N M Backspace
        Row {
            id: row3
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            property real availableWidth: width - spacing * 8
            
            // Shift key (wider)
            Key {
                width: row3.availableWidth * 0.15
                text: "shift"
                iconName: layout.capsLock ? "chevrons-up" : "chevron-up"
                isSpecial: true
                highlighted: layout.shifted || layout.capsLock
                
                onClicked: {
                    layout.shiftClicked()
                }
            }
            
            // Letter keys (equal width)
            Repeater {
                model: row3Keys
                
                Key {
                    width: row3.availableWidth * 0.10
                    text: modelData.char
                    displayText: layout.shifted || layout.capsLock ? modelData.char.toUpperCase() : modelData.char
                    alternateChars: modelData.alts
                    
                    onClicked: {
                        layout.keyClicked(displayText)
                    }
                    
                    onAlternateSelected: function(character) {
                        layout.keyClicked(character)
                    }
                }
            }
            
            // Backspace key (wider)
            Key {
                id: backspaceKey
                width: row3.availableWidth * 0.15
                text: "backspace"
                iconName: "delete"
                isSpecial: true
                
                onClicked: {
                    // Only fire on short tap (not long press)
                    if (!backspaceRepeatTimer.running) {
                        layout.backspaceClicked()
                    }
                }
                
                onPressAndHold: {
                    // Start repeat timer on long press
                    backspaceRepeatTimer.start()
                }
                
                onReleased: {
                    // Stop repeat when released
                    backspaceRepeatTimer.stop()
                }
            }
            
            // Backspace repeat timer (managed at layout level)
            Timer {
                id: backspaceRepeatTimer
                interval: 50  // Delete every 50ms when holding
                repeat: true
                onTriggered: {
                    layout.backspaceClicked()
                }
            }
        }
        
        // Separator line between Row 3 and Row 4
        Rectangle {
            width: parent.width
            height: Math.round(2 * Constants.scaleFactor)
            color: "#666666"
            opacity: 1.0
        }
        
        // Row 4: 123, Comma, Space, Dismiss, Period, Enter (BlackBerry 10 exact style)
        Row {
            id: row4
            width: parent.width
            spacing: Math.round(1 * Constants.scaleFactor)
            property real availableWidth: width - spacing * 5
            
            // 123 key (switch to numbers)
            Key {
                width: row4.availableWidth * 0.12
                text: "123"
                displayText: "123"
                isSpecial: true
                
                onClicked: {
                    layout.layoutSwitchClicked("symbols")
                }
            }
            
            // Emoji key (replaces comma)
            Key {
                width: row4.availableWidth * 0.08
                text: "emoji"
                displayText: "😀"
                isSpecial: true
                
                // Ensure the emoji icon renders correctly
                fontFamily: "Noto Color Emoji"
                
                onClicked: {
                    layout.layoutSwitchClicked("emoji")
                }
            }
            
            // Space bar (MASSIVE - 50% of row)
            Key {
                width: row4.availableWidth * 0.50
                text: " "
                displayText: "space"
                isSpecial: true
                
                onClicked: {
                    layout.spaceClicked()
                }
            }
            
            // Dismiss key (keyboard down icon) - LEFT OF ENTER
            Key {
                width: row4.availableWidth * 0.08
                text: "dismiss"
                iconName: "chevron-down"
                isSpecial: true
                
                onClicked: {
                    layout.dismissClicked()
                }
            }
            
            // Period key
            Key {
                width: row4.availableWidth * 0.08
                text: "."
                displayText: "."
                
                onClicked: {
                    layout.keyClicked(".")
                }
            }
            
            // Enter key (rightmost)
            Key {
                width: row4.availableWidth * 0.14
                text: "enter"
                iconName: "corner-down-left"
                isSpecial: true
                
                onClicked: {
                    layout.enterClicked()
                }
            }
        }
    }
}


