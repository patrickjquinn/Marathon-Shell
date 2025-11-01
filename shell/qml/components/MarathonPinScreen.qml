import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
import MarathonUI.Theme

// High-Performance PIN Entry Screen with Frosted Glass Effect
Item {
    id: pinScreen
    anchors.fill: parent
    
    signal pinCorrect()
    signal cancelled()
    
    property string pin: ""
    property string error: ""
    property string correctPin: "147147"
    property real entryProgress: 0.0
    
    // Fade in
    opacity: entryProgress
    scale: 0.98 + (entryProgress * 0.02)
    
    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }
    
    Behavior on scale {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
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
    
    // Wallpaper background (source for blur)
    Image {
        id: wallpaperSource
        anchors.fill: parent
        source: WallpaperStore.path
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        z: 0
    }
    
    // Frosted glass overlay covering entire screen
    Rectangle {
        id: glassRect
        anchors.fill: parent
        color: "#1a1a1a"
        opacity: 0.5
        z: 1
        
        // Capture wallpaper for blurring
        ShaderEffectSource {
            id: wallpaperCapture
            anchors.fill: parent
            sourceItem: wallpaperSource
            sourceRect: Qt.rect(0, 0, width, height)
            visible: false
        }
        
        // Apply blur effect (Qt6 MultiEffect)
        MultiEffect {
            anchors.fill: parent
            source: wallpaperCapture
            blurEnabled: true
            blur: 1.0
            blurMax: 64
            blurMultiplier: 1.0
            saturation: 0.3
            brightness: -0.2
        }
    }
    
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(-20 * Constants.scaleFactor)
        spacing: Math.round(48 * Constants.scaleFactor)
        z: 100  // PIN UI on top of blur
        
        // GPU layer for column content
        layer.enabled: true
        layer.smooth: true
        
        // Header
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(24 * Constants.scaleFactor)
            
            // Lock icon - larger and cleaner
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(80 * Constants.scaleFactor)
                height: Math.round(80 * Constants.scaleFactor)
                radius: Math.round(40 * Constants.scaleFactor)
                color: MColors.surface
                antialiasing: true
                
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, 0.2)
                    shadowBlur: 0.4
                    shadowVerticalOffset: 4
                }
                
                Icon {
                    name: "lock"
                    size: Math.round(40 * Constants.scaleFactor)
                    color: MColors.accentBright
                    anchors.centerIn: parent
                }
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Enter PIN"
                color: MColors.text
                font.pixelSize: Math.round(28 * Constants.scaleFactor)
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }
        }
        
        // PIN dots - cleaner, larger
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(16 * Constants.scaleFactor)
            
            Repeater {
                model: 6
                
                Rectangle {
                    width: Math.round(14 * Constants.scaleFactor)
                    height: Math.round(14 * Constants.scaleFactor)
                    radius: Math.round(7 * Constants.scaleFactor)
                    color: index < pin.length ? MColors.accentBright : "transparent"
                    border.width: 2
                    border.color: index < pin.length ? MColors.accentBright : MColors.borderLight
                    antialiasing: true
                    
                    // Simple, fast animations
                    Behavior on color {
                        ColorAnimation { duration: 100 }
                    }
                    
                    Behavior on border.color {
                        ColorAnimation { duration: 100 }
                    }
                    
                    // Quick scale pulse
                    scale: (index === pin.length - 1 && pin.length > 0) ? 1.3 : 1.0
                    
                    Behavior on scale {
                        NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                    }
                }
            }
        }
        
        // Error message
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: error
            color: MColors.errorBright
            font.pixelSize: Math.round(16 * Constants.scaleFactor)
            font.weight: Font.Medium
            visible: error !== ""
            height: Math.round(24 * Constants.scaleFactor)
            opacity: error !== "" ? 1.0 : 0.0
            renderType: Text.NativeRendering
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
            
            // Simple shake
            SequentialAnimation on x {
                running: error !== ""
                NumberAnimation { to: 8; duration: 40 }
                NumberAnimation { to: -8; duration: 40 }
                NumberAnimation { to: 4; duration: 40 }
                NumberAnimation { to: -4; duration: 40 }
                NumberAnimation { to: 0; duration: 40 }
            }
        }
        
        // Number pad - larger, cleaner, faster
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(16 * Constants.scaleFactor)
            
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                columnSpacing: Math.round(16 * Constants.scaleFactor)
                rowSpacing: Math.round(16 * Constants.scaleFactor)
                
                // GPU layer for grid
                layer.enabled: true
                layer.smooth: true
                
                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
                    
                    Rectangle {
                        id: numButton
                        width: Math.round(80 * Constants.scaleFactor)
                        height: Math.round(80 * Constants.scaleFactor)
                        radius: Math.round(40 * Constants.scaleFactor)
                        color: numMouseArea.pressed ? MColors.surface2 : MColors.surface
                        antialiasing: true
                        
                        // Fast color transition
                        Behavior on color {
                            ColorAnimation { duration: 80 }
                        }
                        
                        // Subtle shadow
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: Qt.rgba(0, 0, 0, 0.15)
                            shadowBlur: 0.3
                            shadowVerticalOffset: 2
                        }
                        
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: MColors.text
                            font.pixelSize: Math.round(32 * Constants.scaleFactor)
                            font.weight: Font.Light
                            renderType: Text.NativeRendering
                        }
                        
                        // Simple scale - fast
                        scale: numMouseArea.pressed ? 0.88 : 1.0
                        
                        Behavior on scale {
                            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
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
                spacing: Math.round(16 * Constants.scaleFactor)
                
                // Empty space for alignment
                Item { 
                    width: Math.round(80 * Constants.scaleFactor)
                    height: Math.round(80 * Constants.scaleFactor)
                }
                
                // Zero button
                Rectangle {
                    width: Math.round(80 * Constants.scaleFactor)
                    height: Math.round(80 * Constants.scaleFactor)
                    radius: Math.round(40 * Constants.scaleFactor)
                    color: zeroMouseArea.pressed ? MColors.surface2 : MColors.surface
                    antialiasing: true
                    
                    Behavior on color {
                        ColorAnimation { duration: 80 }
                    }
                    
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, 0.15)
                        shadowBlur: 0.3
                        shadowVerticalOffset: 2
                    }
                    
                    Text {
                        anchors.centerIn: parent
                        text: "0"
                        color: MColors.text
                        font.pixelSize: Math.round(32 * Constants.scaleFactor)
                        font.weight: Font.Light
                        renderType: Text.NativeRendering
                    }
                    
                    scale: zeroMouseArea.pressed ? 0.88 : 1.0
                    
                    Behavior on scale {
                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
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
                    width: Math.round(80 * Constants.scaleFactor)
                    height: Math.round(80 * Constants.scaleFactor)
                    radius: Math.round(40 * Constants.scaleFactor)
                    color: clearMouseArea.pressed ? MColors.surface2 : MColors.surface
                    antialiasing: true
                    
                    Behavior on color {
                        ColorAnimation { duration: 80 }
                    }
                    
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Qt.rgba(0, 0, 0, 0.15)
                        shadowBlur: 0.3
                        shadowVerticalOffset: 2
                    }
                    
                    Icon {
                        name: "delete"
                        size: Math.round(28 * Constants.scaleFactor)
                        color: MColors.textSecondary
                        anchors.centerIn: parent
                    }
                    
                    scale: clearMouseArea.pressed ? 0.88 : 1.0
                    
                    Behavior on scale {
                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
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
            font.pixelSize: Math.round(16 * Constants.scaleFactor)
            font.weight: Font.Medium
            opacity: cancelMouseArea.pressed ? 0.5 : 0.8
            renderType: Text.NativeRendering
            
            Behavior on opacity {
                NumberAnimation { duration: 80 }
            }
            
            MouseArea {
                id: cancelMouseArea
                anchors.fill: parent
                anchors.margins: Math.round(-16 * Constants.scaleFactor)
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
                // Small delay for visual feedback
                verifyTimer.start()
            }
        }
    }
    
    Timer {
        id: verifyTimer
        interval: 100
        onTriggered: verifyPin()
    }
    
    function verifyPin() {
        if (pin === correctPin) {
            HapticService.medium()
            Logger.info("PinScreen", "✅ PIN correct")
            pinCorrect()
        } else {
            HapticService.heavy()
            Logger.warn("PinScreen", "❌ PIN incorrect")
            error = "Incorrect PIN"
            errorTimer.start()
        }
    }
    
    Timer {
        id: errorTimer
        interval: 1200
        onTriggered: {
            pin = ""
            error = ""
        }
    }
    
    function reset() {
        pin = ""
        error = ""
        entryProgress = 0.0
    }
    
    function show() {
        pin = ""
        error = ""
        entryProgress = 1.0
        forceActiveFocus()
        Logger.info("PinScreen", "📱 PIN screen shown")
    }
}
