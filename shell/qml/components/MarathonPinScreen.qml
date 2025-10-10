import QtQuick
import "../theme"
import "../stores"
import "."

// PIN Entry Screen - shown after swipe-up unlock
Rectangle {
    id: pinScreen
    anchors.fill: parent
    color: "#000000"
    
    signal pinCorrect()
    signal cancelled()
    
    property string pin: ""
    property string error: ""
    property string correctPin: "147147"
    property real entryProgress: 0.0  // 0.0 = hidden, 1.0 = shown
    
    // Fade and scale in
    opacity: entryProgress
    scale: 0.95 + (entryProgress * 0.05)
    
    Behavior on opacity {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }
    
    Behavior on scale {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutBack
            easing.overshoot: 1.1
        }
    }
    
    // Dim background
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.95
    }
    
    Column {
        anchors.centerIn: parent
        spacing: 40
        
        // Title
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Enter PIN"
            color: Colors.text
            font.pixelSize: 28
            font.weight: Font.Medium
        }
        
        // PIN dots indicator
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            
            Repeater {
                model: 6
                
                Rectangle {
                    width: 16
                    height: 16
                    radius: 8
                    color: index < pin.length ? Colors.accent : "transparent"
                    border.color: Colors.text
                    border.width: 2
                    
                    Behavior on color {
                        ColorAnimation { duration: 150 }
                    }
                    
                    // Pulse animation when filled
                    SequentialAnimation on scale {
                        running: index === pin.length - 1 && pin.length > 0
                        NumberAnimation { to: 1.3; duration: 100 }
                        NumberAnimation { to: 1.0; duration: 100 }
                    }
                }
            }
        }
        
        // Error message
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: error
            color: Colors.error
            font.pixelSize: Typography.sizeBody
            visible: error !== ""
            height: visible ? implicitHeight : 0
            
            // Shake animation on error
            SequentialAnimation on x {
                running: error !== ""
                loops: 3
                NumberAnimation { to: 10; duration: 50 }
                NumberAnimation { to: -10; duration: 50 }
                NumberAnimation { to: 0; duration: 50 }
            }
        }
        
        // Number pad
        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            spacing: 20
            
            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", ""]
                
                Rectangle {
                    width: 80
                    height: 80
                    radius: 40
                    color: modelData !== "" ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    border.color: modelData !== "" ? Qt.rgba(1, 1, 1, 0.3) : "transparent"
                    border.width: 2
                    visible: modelData !== ""
                    
                    // Glassy effect
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.15) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.1) }
                        }
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        color: Colors.text
                        font.pixelSize: 32
                        font.weight: Font.Light
                    }
                    
                    MouseArea {
                        id: buttonArea
                        anchors.fill: parent
                        enabled: modelData !== ""
                        
                        onPressed: {
                            parent.scale = 0.9
                            parent.opacity = 0.7
                        }
                        
                        onReleased: {
                            parent.scale = 1.0
                            parent.opacity = 1.0
                        }
                        
                        onClicked: {
                            if (modelData !== "") {
                                handleInput(modelData)
                            }
                        }
                    }
                    
                    Behavior on scale {
                        NumberAnimation { duration: 100 }
                    }
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }
                }
            }
        }
        
        // Backspace button
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 180
            height: 60
            radius: 30
            color: Qt.rgba(1, 1, 1, 0.1)
            border.color: Qt.rgba(1, 1, 1, 0.3)
            border.width: 2
            
            Text {
                anchors.centerIn: parent
                text: "← Clear"
                color: Colors.text
                font.pixelSize: 20
            }
            
            MouseArea {
                anchors.fill: parent
                
                onPressed: {
                    parent.scale = 0.95
                    parent.opacity = 0.7
                }
                
                onReleased: {
                    parent.scale = 1.0
                    parent.opacity = 1.0
                }
                
                onClicked: {
                    pin = ""
                    error = ""
                }
            }
            
            Behavior on scale {
                NumberAnimation { duration: 100 }
            }
            
            Behavior on opacity {
                NumberAnimation { duration: 100 }
            }
        }
    }
    
    // Cancel button (top left)
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 20
        width: 100
        height: 44
        radius: 22
        color: Qt.rgba(1, 1, 1, 0.1)
        border.color: Qt.rgba(1, 1, 1, 0.3)
        border.width: 1
        
        Text {
            anchors.centerIn: parent
            text: "Cancel"
            color: Colors.text
            font.pixelSize: 16
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                pin = ""
                error = ""
                cancelled()
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

