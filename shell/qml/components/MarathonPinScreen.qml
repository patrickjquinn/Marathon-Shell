import QtQuick
import MarathonOS.Shell

// Modern PIN Entry Screen - Marathon Design System
Rectangle {
    id: pinScreen
    anchors.fill: parent
    color: MColors.background
    
    signal pinCorrect()
    signal cancelled()
    
    property string pin: ""
    property string error: ""
    property string correctPin: "147147"
    property real entryProgress: 0.0  // 0.0 = hidden, 1.0 = shown
    
    // Fade and scale in
    opacity: entryProgress
    scale: 0.97 + (entryProgress * 0.03)
    
    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.moderate
            easing.type: Easing.OutCubic
        }
    }
    
    Behavior on scale {
        NumberAnimation {
            duration: MMotion.moderate
            easing.type: Easing.OutCubic
        }
    }
    
    Keys.onPressed: function(event) {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            var digit = String.fromCharCode(event.key)
            handleInput(digit)
            event.accepted = true
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            pin = ""
            error = ""
            event.accepted = true
        }
    }
    
    focus: visible && entryProgress >= 1.0
    
    Column {
        anchors.centerIn: parent
        spacing: Math.round(40 * Constants.scaleFactor)
        
        // Header section
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(20 * Constants.scaleFactor)
            
            // Lock icon using Lucide
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(64 * Constants.scaleFactor)
                height: Math.round(64 * Constants.scaleFactor)
                radius: Constants.borderRadiusMedium
                color: MColors.surface2
                border.width: Constants.borderWidthMedium
                border.color: MColors.borderOuter
                antialiasing: Constants.enableAntialiasing
                
                // Inner border for depth
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: parent.radius
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: MColors.borderInner
                    antialiasing: parent.antialiasing
                }
                
                Icon {
                    name: "lock"
                    size: Math.round(32 * Constants.scaleFactor)
                    color: MColors.accentBright
                    anchors.centerIn: parent
                }
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Enter PIN"
                color: MColors.text
                font.pixelSize: Math.round(22 * Constants.scaleFactor)
                font.weight: Font.DemiBold
            }
        }
        
        // PIN dots indicator - modern filled circles
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(12 * Constants.scaleFactor)
            
            Repeater {
                model: 6
                
                Rectangle {
                    width: Math.round(10 * Constants.scaleFactor)
                    height: Math.round(10 * Constants.scaleFactor)
                    radius: Math.round(5 * Constants.scaleFactor)
                    color: index < pin.length ? MColors.accentBright : MColors.surface1
                    border.width: index < pin.length ? 0 : 1
                    border.color: MColors.borderLight
                    antialiasing: true
                    
                    Behavior on color {
                        ColorAnimation { duration: MMotion.quick; easing.type: Easing.OutCubic }
                    }
                    
                    Behavior on scale {
                        SpringAnimation { 
                            spring: MMotion.springMedium
                            damping: MMotion.dampingMedium
                            epsilon: MMotion.epsilon
                        }
                    }
                    
                    // Pulse animation when filled
                    scale: (index === pin.length - 1 && pin.length > 0) ? 1.4 : 1.0
                }
            }
        }
        
        // Error message
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: error
            color: MColors.errorBright
            font.pixelSize: Math.round(14 * Constants.scaleFactor)
            font.weight: Font.Medium
            visible: error !== ""
            height: Math.round(20 * Constants.scaleFactor)
            opacity: error !== "" ? 1.0 : 0.0
            
            Behavior on opacity {
                NumberAnimation { duration: MMotion.quick }
            }
            
            // Shake animation on error
            SequentialAnimation on x {
                running: error !== ""
                NumberAnimation { to: 6; duration: 50 }
                NumberAnimation { to: -6; duration: 50 }
                NumberAnimation { to: 3; duration: 50 }
                NumberAnimation { to: -3; duration: 50 }
                NumberAnimation { to: 0; duration: 50 }
            }
        }
        
        // Marathon-style number pad
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(12 * Constants.scaleFactor)
            
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                columnSpacing: Math.round(12 * Constants.scaleFactor)
                rowSpacing: Math.round(12 * Constants.scaleFactor)
                
                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
                    
                    Rectangle {
                        id: numButton
                        width: Math.round(64 * Constants.scaleFactor)
                        height: Math.round(64 * Constants.scaleFactor)
                        radius: Constants.borderRadiusSharp
                        color: MColors.surface1
                        border.width: Constants.borderWidthMedium
                        border.color: numMouseArea.pressed ? MColors.borderHighlight : MColors.borderOuter
                        antialiasing: Constants.enableAntialiasing
                        
                        Behavior on border.color {
                            ColorAnimation { duration: MMotion.quick; easing.type: Easing.OutCubic }
                        }
                        
                        // Inner border for depth
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: parent.radius - 1
                            color: "transparent"
                            border.width: Constants.borderWidthThin
                            border.color: numMouseArea.pressed ? MColors.accentSubtle : MColors.borderInner
                            antialiasing: parent.antialiasing
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: MColors.text
                            font.pixelSize: Math.round(24 * Constants.scaleFactor)
                            font.weight: Font.Light
                        }
                        
                        scale: numMouseArea.pressed ? 0.92 : 1.0
                        
                        Behavior on scale {
                            SpringAnimation { 
                                spring: MMotion.springMedium
                                damping: MMotion.dampingMedium
                                epsilon: MMotion.epsilon
                            }
                        }
                        
                        MouseArea {
                            id: numMouseArea
                            anchors.fill: parent
                            onClicked: {
                                HapticService.light()
                                handleInput(modelData)
                            }
                        }
                    }
                }
            }
            
            // Bottom row: 0 and backspace
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(12 * Constants.scaleFactor)
                
                // Empty space for alignment
                Item { 
                    width: Math.round(64 * Constants.scaleFactor)
                    height: Math.round(64 * Constants.scaleFactor)
                }
                
                // Zero button
                Rectangle {
                    width: Math.round(64 * Constants.scaleFactor)
                    height: Math.round(64 * Constants.scaleFactor)
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface1
                    border.width: Constants.borderWidthMedium
                    border.color: zeroMouseArea.pressed ? MColors.borderHighlight : MColors.borderOuter
                    antialiasing: Constants.enableAntialiasing
                    
                    Behavior on border.color {
                        ColorAnimation { duration: MMotion.quick; easing.type: Easing.OutCubic }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.width: Constants.borderWidthThin
                        border.color: zeroMouseArea.pressed ? MColors.accentSubtle : MColors.borderInner
                        antialiasing: parent.antialiasing
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "0"
                        color: MColors.text
                        font.pixelSize: Math.round(24 * Constants.scaleFactor)
                        font.weight: Font.Light
                    }
                    
                    scale: zeroMouseArea.pressed ? 0.92 : 1.0
                    
                    Behavior on scale {
                        SpringAnimation { 
                            spring: MMotion.springMedium
                            damping: MMotion.dampingMedium
                            epsilon: MMotion.epsilon
                        }
                    }
                    
                    MouseArea {
                        id: zeroMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light()
                            handleInput("0")
                        }
                    }
                }
                
                // Backspace button
                Rectangle {
                    width: Math.round(64 * Constants.scaleFactor)
                    height: Math.round(64 * Constants.scaleFactor)
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface1
                    border.width: Constants.borderWidthMedium
                    border.color: clearMouseArea.pressed ? MColors.borderHighlight : MColors.borderOuter
                    antialiasing: Constants.enableAntialiasing
                    
                    Behavior on border.color {
                        ColorAnimation { duration: MMotion.quick; easing.type: Easing.OutCubic }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: parent.radius - 1
                        color: "transparent"
                        border.width: Constants.borderWidthThin
                        border.color: clearMouseArea.pressed ? MColors.accentSubtle : MColors.borderInner
                        antialiasing: parent.antialiasing
                    }
                    
                    Icon {
                        name: "delete"
                        size: Math.round(20 * Constants.scaleFactor)
                        color: MColors.textSecondary
                        anchors.centerIn: parent
                    }
                    
                    scale: clearMouseArea.pressed ? 0.92 : 1.0
                    
                    Behavior on scale {
                        SpringAnimation { 
                            spring: MMotion.springMedium
                            damping: MMotion.dampingMedium
                            epsilon: MMotion.epsilon
                        }
                    }
                    
                    MouseArea {
                        id: clearMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light()
                            pin = ""
                            error = ""
                        }
                    }
                }
            }
        }
        
        // Cancel button
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Cancel"
            color: MColors.textSecondary
            font.pixelSize: Math.round(15 * Constants.scaleFactor)
            font.weight: Font.Normal
            opacity: cancelMouseArea.pressed ? 0.5 : 0.7
            
            Behavior on opacity {
                NumberAnimation { duration: MMotion.quick }
            }
            
            MouseArea {
                id: cancelMouseArea
                anchors.fill: parent
                anchors.margins: Math.round(-12 * Constants.scaleFactor)
                onClicked: {
                    HapticService.light()
                    cancelled()
                }
            }
        }
    }
    
    function handleInput(digit) {
        if (pin.length < 6) {
            pin += digit
            error = ""
            
            if (pin.length === 6) {
                verifyPin()
            }
        }
    }
    
    function verifyPin() {
        if (pin === correctPin) {
            console.log("✅ PIN correct!")
            pinCorrect()
        } else {
            console.log("❌ PIN incorrect!")
            error = "Incorrect PIN"
            
            // Clear PIN after a delay
            errorTimer.start()
        }
    }
    
    function reset() {
        pin = ""
        error = ""
        entryProgress = 0.0
    }
    
    function show() {
        pin = ""  // Clear PIN when showing
        error = ""
        entryProgress = 1.0
        console.log("📱 PIN screen shown, PIN cleared")
    }
    
    Timer {
        id: errorTimer
        interval: 1500
        repeat: false
        onTriggered: {
            pin = ""
            error = ""
        }
    }
}
