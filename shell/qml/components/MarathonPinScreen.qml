import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

// PIN Entry Screen - shown after swipe-up unlock
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
    
    Rectangle {
        anchors.fill: parent
        color: MColors.background
        opacity: 0.95
    }
    
    Column {
        anchors.centerIn: parent
        spacing: Constants.spacingXXLarge
        
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Enter PIN"
            color: MColors.text
            font.pixelSize: Typography.sizeXLarge
            font.weight: Font.Medium
        }
        
        // PIN dots indicator
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingMedium
            
            Repeater {
                model: 6
                
                Rectangle {
                    width: 16
                    height: 16
                    radius: Constants.borderRadiusSharp
                    color: index < pin.length ? MColors.accentBright : "transparent"
                    border.color: MColors.text
                    border.width: 2
                    antialiasing: Constants.enableAntialiasing
                    
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
            color: MColors.error
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
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingLarge
            
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                columnSpacing: 20
                rowSpacing: 20
                
                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
                    
                    Rectangle {
                        width: 80
                        height: Constants.hubHeaderHeight
                        radius: Constants.borderRadiusSharp
                        color: MColors.surface
                        border.width: Constants.borderWidthMedium
                        border.color: MColors.borderOuter
                        antialiasing: Constants.enableAntialiasing
                        
                        Behavior on border.color {
                            ColorAnimation { duration: 200 }
                        }
                        
                        // Inner border for depth
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Constants.borderRadiusSharp
                            color: "transparent"
                            border.width: Constants.borderWidthThin
                            border.color: MColors.borderInner
                            antialiasing: Constants.enableAntialiasing
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: MColors.text
                            font.pixelSize: Constants.fontSizeXXLarge
                            font.weight: Font.Light
                            opacity: numMouseArea.pressed ? 1.0 : 0.9
                            
                            Behavior on opacity {
                                NumberAnimation { duration: 200 }
                            }
                        }
                        
                        transform: [
                            Scale {
                                origin.x: 40
                                origin.y: 40
                                xScale: numMouseArea.pressed ? 0.88 : 1.0
                                yScale: numMouseArea.pressed ? 0.88 : 1.0
                                
                                Behavior on xScale {
                                    NumberAnimation { 
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on yScale {
                                    NumberAnimation { 
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        ]
                        
                        MouseArea {
                            id: numMouseArea
                            anchors.fill: parent
                            
                            
                            onClicked: handleInput(modelData)
                        }
                    }
                }
            }
            
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Constants.spacingLarge
                
                Item { width: 80; height: Constants.hubHeaderHeight }
                
                Rectangle {
                    width: 80
                    height: Constants.hubHeaderHeight
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface
                    border.width: Constants.borderWidthMedium
                    border.color: MColors.borderOuter
                    antialiasing: Constants.enableAntialiasing
                    
                    Behavior on border.color {
                        ColorAnimation { duration: 200 }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: Constants.borderRadiusSharp
                        color: "transparent"
                        border.width: Constants.borderWidthThin
                        border.color: MColors.borderInner
                        antialiasing: Constants.enableAntialiasing
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "0"
                        color: MColors.text
                        font.pixelSize: Constants.fontSizeXXLarge
                        font.weight: Font.Light
                        opacity: zeroMouseArea.pressed ? 1.0 : 0.9
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 200 }
                        }
                    }
                    
                    transform: [
                        Scale {
                            origin.x: 40
                            origin.y: 40
                            xScale: zeroMouseArea.pressed ? 0.88 : 1.0
                            yScale: zeroMouseArea.pressed ? 0.88 : 1.0
                            
                            Behavior on xScale {
                                NumberAnimation { 
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on yScale {
                                NumberAnimation { 
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    ]
                    
                    MouseArea {
                        id: zeroMouseArea
                        anchors.fill: parent
                        
                        
                        onClicked: handleInput("0")
                    }
                }
                
                Rectangle {
                    width: 80
                    height: Constants.hubHeaderHeight
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface1
                    border.width: Constants.borderWidthMedium
                    border.color: MColors.borderOuter
                    antialiasing: Constants.enableAntialiasing
                    
                    Behavior on border.color {
                        ColorAnimation { duration: 200 }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: Constants.borderRadiusSharp
                        color: "transparent"
                        border.width: Constants.borderWidthThin
                        border.color: MColors.borderInner
                        antialiasing: Constants.enableAntialiasing
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "←"
                        color: MColors.text
                        font.pixelSize: 26
                        font.weight: Font.Light
                        opacity: clearMouseArea.pressed ? 1.0 : 0.8
                        
                        Behavior on opacity {
                            NumberAnimation { duration: 200 }
                        }
                    }
                    
                    transform: [
                        Scale {
                            origin.x: 40
                            origin.y: 40
                            xScale: clearMouseArea.pressed ? 0.88 : 1.0
                            yScale: clearMouseArea.pressed ? 0.88 : 1.0
                            
                            Behavior on xScale {
                                NumberAnimation { 
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on yScale {
                                NumberAnimation { 
                                    duration: 200
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    ]
                    
                    MouseArea {
                        id: clearMouseArea
                        anchors.fill: parent
                        
                        
                        onClicked: {
                            pin = ""
                            error = ""
                        }
                    }
                }
            }
            
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0
                
                Text {
                    text: "Cancel"
                    color: MColors.text
                    font.pixelSize: Typography.sizeBody
                    font.weight: Font.Normal
                    opacity: cancelMouseArea.pressed ? 0.5 : 0.7
                    
                    Behavior on opacity {
                        NumberAnimation { duration: Constants.animationDurationFast }
                    }
                    
                    MouseArea {
                        id: cancelMouseArea
                        anchors.fill: parent
                        anchors.margins: -20
                        onClicked: cancelled()
                    }
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

