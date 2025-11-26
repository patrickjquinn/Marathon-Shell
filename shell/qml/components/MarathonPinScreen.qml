import QtQuick
import QtQuick.Effects
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Feedback

// High-Performance PIN Entry Screen with Frosted Glass Effect
Item {
    id: pinScreen
    anchors.fill: parent
    
    signal pinCorrect()
    signal cancelled()
    
    property string pin: ""
    property string password: ""
    property string error: ""
    property real entryProgress: 0.0
    property bool passwordMode: false  // true = password input, false = PIN pad
    property bool biometricInProgress: false
    property bool authenticating: false  // Show spinner when validating
    
    // NO fade animation - opacity controlled by parent state for instant security
    // Pre-render for zero-latency display
    layer.enabled: true
    layer.smooth: true
    
    // Update SessionStore to show lock icon in status bar when PIN screen visible
    onVisibleChanged: {
        if (visible) {
            SessionStore.isOnLockScreen = true
            Logger.info("PinScreen", "PIN screen visible - showing lock icon in status bar")
        } else {
            SessionStore.isOnLockScreen = false
            Logger.info("PinScreen", "PIN screen hidden - showing clock in status bar")
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
    
    // Security Manager connections
    Connections {
        target: SecurityManagerCpp
        
        function onAuthenticationSuccess() {
            Logger.info("PinScreen", " Authentication successful, hiding spinner")
            authenticating = false
            HapticService.medium()
            
            // Clear password field for security
            pin = ""
            password = ""
            passwordTextInput.text = ""
            
            // Trigger unlock animation in status bar
            SessionStore.triggerUnlockAnimation()
            
            // Delay unlock to allow animation to play (350ms for smooth unlock visual)
            unlockDelayTimer.start()
        }
        
        function onAuthenticationFailed(reason) {
            Logger.warn("PinScreen", " Authentication failed, hiding spinner:", reason)
            authenticating = false
            HapticService.heavy()
            error = reason
            errorTimer.start()
            biometricInProgress = false
            
            // Trigger shake animation in status bar
            SessionStore.triggerShakeAnimation()
        }
        
        function onBiometricPrompt(message) {
            Logger.info("PinScreen", "👆 Biometric prompt:", message)
            error = message
        }
        
        function onLockoutStateChanged() {
            if (SecurityManagerCpp.isLockedOut) {
                var secs = SecurityManagerCpp.lockoutSecondsRemaining
                error = "Locked for " + secs + "s"
                Logger.warn("PinScreen", "🔒 Account locked for", secs, "seconds")
            }
        }
    }
    
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
        color: MColors.background
        opacity: 0.95
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
    
    // Solid background overlay for better contrast
    Rectangle {
        anchors.fill: parent
        color: MColors.overlay
        z: 2
    }
    
    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(-20 * Constants.scaleFactor)
        spacing: Math.round(24 * Constants.scaleFactor) // Reduced from 40
        z: 100  // PIN UI on top of blur
        
        // GPU layer for column content
        layer.enabled: true
        layer.smooth: true
        
        // Header
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(16 * Constants.scaleFactor) // Reduced from 24
            
            // Lock icon removed - now shown in status bar for consistency
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: passwordMode ? "Enter Password" : "Enter PIN"
                color: MColors.text
                font.pixelSize: Math.round(24 * Constants.scaleFactor) // Reduced from 28
                font.weight: Font.Medium
                renderType: Text.NativeRendering
                
                Behavior on text {
                    SequentialAnimation {
                        NumberAnimation { 
                            target: parent.children[1]
                            property: "opacity"
                            to: 0
                            duration: 100
                        }
                        PropertyAction { target: parent.children[1]; property: "text" }
                        NumberAnimation { 
                            target: parent.children[1]
                            property: "opacity"
                            to: 1
                            duration: 100
                        }
                    }
                }
            }
        }
        
        // PIN dots with loading spinner
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(16 * Constants.scaleFactor)
            
            // PIN dots
            Row {
                id: pinCircles
                spacing: Math.round(16 * Constants.scaleFactor)
                
                Repeater {
                    model: 6
                    
                    Rectangle {
                        width: Math.round(14 * Constants.scaleFactor)
                        height: Math.round(14 * Constants.scaleFactor)
                        radius: Math.round(7 * Constants.scaleFactor)
                        color: index < pin.length ? MColors.accentBright : "transparent"
                        border.width: 2
                        border.color: index < pin.length ? MColors.accentBright : MColors.borderSubtle
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
            
            // Authentication spinner - aligned with PIN circles center
            MActivityIndicator {
                anchors.verticalCenter: pinCircles.verticalCenter
                size: Math.round(32 * Constants.scaleFactor)
                color: MColors.accentBright
                running: authenticating && !passwordMode
                visible: authenticating && !passwordMode
                opacity: visible ? 1.0 : 0.0
                
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }
        }
        
        // Error message
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(300 * Constants.scaleFactor)
            height: Math.round(40 * Constants.scaleFactor)
            radius: Math.round(8 * Constants.scaleFactor)
            color: Qt.rgba(MColors.error.r, MColors.error.g, MColors.error.b, 0.15)
            visible: error !== ""
            opacity: error !== "" ? 1.0 : 0.0
            
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }
            
            Text {
                anchors.centerIn: parent
                text: error
                color: MColors.error
                font.pixelSize: Math.round(14 * Constants.scaleFactor)
                font.weight: Font.Medium
                renderType: Text.NativeRendering
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
        
        // Number pad - larger, cleaner, faster (only visible in PIN mode)
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(12 * Constants.scaleFactor) // Reduced from 16
            visible: !passwordMode
            
            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                columnSpacing: Math.round(16 * Constants.scaleFactor)
                rowSpacing: Math.round(12 * Constants.scaleFactor) // Reduced from 16
                
                // GPU layer for grid
                layer.enabled: true
                layer.smooth: true
                
                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
                    
                    delegate: Item {
                        width: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor) // Reduced from 80
                        height: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor) // Reduced from 80
                        
                        property string digit: modelData
                        
                        MCircularIconButton {
                            anchors.centerIn: parent
                            text: digit
                            iconSize: Math.round(28 * Constants.scaleFactor) // Reduced from 32
                            buttonSize: Math.round(70 * Constants.scaleFactor) // Reduced from 80
                            variant: "secondary"
                            textColor: MColors.textPrimary
                            onClicked: {
                                HapticService.light()
                                handleInput(parent.digit)
                            }
                        }
                    }
                }
            }
            
            // Bottom row: keyboard button, 0, and backspace
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(16 * Constants.scaleFactor)
                
                // Keyboard button (switch to password mode)
                Item { 
                    width: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
                    height: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
                    
                    MCircularIconButton {
                        anchors.centerIn: parent
                        iconName: "keyboard"
                        iconSize: Math.round(24 * Constants.scaleFactor)
                        buttonSize: Math.round(70 * Constants.scaleFactor)
                        variant: "secondary"
                        visible: !passwordMode
                        onClicked: {
                            HapticService.light()
                            switchToPasswordMode()
                        }
                    }
                }
                
                // Zero button
                Item {
                    width: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
                    height: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
                    
                    MCircularIconButton {
                        anchors.centerIn: parent
                        text: "0"
                        iconSize: Math.round(28 * Constants.scaleFactor)
                        buttonSize: Math.round(70 * Constants.scaleFactor)
                        variant: "secondary"
                        textColor: MColors.textPrimary
                        onClicked: {
                            HapticService.light()
                            handleInput("0")
                        }
                    }
                }
                
                // Backspace button
                Item {
                    width: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
                    height: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
                    
                    MCircularIconButton {
                        anchors.centerIn: parent
                        iconName: "delete"
                        iconSize: Math.round(24 * Constants.scaleFactor)
                        buttonSize: Math.round(70 * Constants.scaleFactor)
                        variant: "secondary"
                        iconColor: MColors.textSecondary
                        onClicked: {
                            HapticService.light()
                            pin = ""
                            error = ""
                        }
                    }
                }
            }
        }
        
        // Password input mode (alternative to PIN pad)
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(24 * Constants.scaleFactor)
            visible: passwordMode
            width: Math.round(320 * Constants.scaleFactor)
            
            // Password field with spinner overlay (no layout shift)
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(280 * Constants.scaleFactor)
                height: Math.round(52 * Constants.scaleFactor)
                
                Rectangle {
                    id: passwordField
                    anchors.fill: parent
                    radius: Math.round(12 * Constants.scaleFactor)
                    color: MColors.bb10Surface
                    border.width: 2
                    border.color: passwordTextInput.activeFocus ? MColors.marathonTeal : MColors.borderSubtle
                    
                    Behavior on border.color {
                        ColorAnimation { duration: 200 }
                    }
                    
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Enter password"
                        color: MColors.textSecondary
                        font.pixelSize: Math.round(18 * Constants.scaleFactor)
                        font.family: MTypography.fontFamily
                        visible: passwordTextInput.text.length === 0 && !passwordTextInput.activeFocus
                    }
                    
                    TextInput {
                        id: passwordTextInput
                        anchors.fill: parent
                        anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                        anchors.rightMargin: Math.round(48 * Constants.scaleFactor)  // Extra space for spinner
                        verticalAlignment: TextInput.AlignVCenter
                        color: MColors.textPrimary
                        selectedTextColor: MColors.textOnAccent
                        selectionColor: MColors.marathonTeal
                        font.pixelSize: Math.round(18 * Constants.scaleFactor)
                        font.family: MTypography.fontFamily
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        echoMode: TextInput.Password
                        
                        onAccepted: verifyPasswordInput()
                        onTextChanged: {
                            password = text
                            error = ""
                        }
                    }
                    
                    Component.onCompleted: {
                        if (passwordMode) {
                            Qt.callLater(function() { 
                                passwordTextInput.forceActiveFocus()
                            })
                        }
                    }
                }
                
                // Authentication spinner - overlays on right side of password field
                MActivityIndicator {
                    anchors.right: parent.right
                    anchors.rightMargin: Math.round(12 * Constants.scaleFactor)
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.round(28 * Constants.scaleFactor)
                    color: MColors.accentBright
                    running: authenticating && passwordMode
                    visible: authenticating && passwordMode
                    opacity: visible ? 1.0 : 0.0
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }
                }
            }
            
            // Action buttons - horizontal layout
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                spacing: Math.round(12 * Constants.scaleFactor)
                
                // Secondary button - Use PIN (left)
                MButton {
                    width: (parent.width - parent.spacing) / 2
                    text: "Use PIN"
                    variant: "secondary"
                    onClicked: switchToPINMode()
                }
                
                // Primary button - Unlock (right)
                MButton {
                    width: (parent.width - parent.spacing) / 2
                    text: "Unlock"
                    variant: "primary"
                    enabled: !authenticating
                    onClicked: verifyPasswordInput()
                }
            }
        }
        
        // Fingerprint button (centered, below PIN pad)
        MCircularIconButton {
            anchors.horizontalCenter: parent.horizontalCenter
            iconName: "fingerprint"
            iconSize: Math.round(28 * Constants.scaleFactor)
            buttonSize: Math.round(64 * Constants.scaleFactor)
            variant: "secondary"
            visible: SecurityManagerCpp.fingerprintAvailable && !biometricInProgress && !passwordMode
            enabled: !SecurityManagerCpp.isLockedOut
            onClicked: {
                HapticService.light()
                startBiometric()
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
        // Check if locked out
        if (SecurityManagerCpp.isLockedOut) {
            var secs = SecurityManagerCpp.lockoutSecondsRemaining
            error = "Locked for " + secs + "s"
            HapticService.heavy()
            return
        }
        
        // Show spinner
        Logger.info("PinScreen", "🔄 Starting authentication, showing spinner")
        authenticating = true
        
        // Authenticate based on current mode
        if (SecurityManagerCpp.hasQuickPIN && !passwordMode) {
            // Quick PIN authentication
            SecurityManagerCpp.authenticateQuickPIN(pin)
        } else {
            // System password authentication via PAM
            var inputPassword = passwordMode ? password : pin
            SecurityManagerCpp.authenticatePassword(inputPassword)
        }
    }
    
    function verifyPasswordInput() {
        if (SecurityManagerCpp.isLockedOut) {
            var secs = SecurityManagerCpp.lockoutSecondsRemaining
            error = "Locked for " + secs + "s"
            HapticService.heavy()
            return
        }
        
        if (password.trim().length === 0) {
            error = "Password cannot be empty"
            HapticService.light()
            return
        }
        
        // Show spinner
        Logger.info("PinScreen", "🔄 Starting password authentication, showing spinner")
        authenticating = true
        
        SecurityManagerCpp.authenticatePassword(password)
    }
    
    function startBiometric() {
        if (SecurityManagerCpp.isLockedOut) {
            var secs = SecurityManagerCpp.lockoutSecondsRemaining
            error = "Locked for " + secs + "s"
            HapticService.heavy()
            return
        }
        
        if (!SecurityManagerCpp.fingerprintAvailable) {
            error = "Fingerprint not enrolled"
            HapticService.light()
            return
        }
        
        biometricInProgress = true
        error = "Place your finger..."
        SecurityManagerCpp.authenticateBiometric(0)  // 0 = Fingerprint
    }
    
    function switchToPasswordMode() {
        passwordMode = true
        pin = ""
        password = ""
        passwordTextInput.text = ""  // Explicitly clear TextInput
        error = ""
        Logger.info("PinScreen", "Switched to password mode")
        
        // Focus the password field
        Qt.callLater(function() {
            passwordTextInput.forceActiveFocus()
        })
    }
    
    function switchToPINMode() {
        passwordMode = false
        pin = ""
        password = ""
        passwordTextInput.text = ""  // Explicitly clear TextInput
        error = ""
        Logger.info("PinScreen", "Switched to PIN mode")
    }
    
    Timer {
        id: errorTimer
        interval: 1200
        onTriggered: {
            pin = ""
            error = ""
        }
    }
    
    Timer {
        id: unlockDelayTimer
        interval: 350  // Match unlock animation duration
        onTriggered: {
            pinCorrect()  // Now emit the unlock signal
        }
    }
    
    function reset() {
        pin = ""
        password = ""
        passwordTextInput.text = ""  // Explicitly clear TextInput for security
        error = ""
        entryProgress = 0.0
    }
    
    function show() {
        pin = ""
        password = ""
        passwordTextInput.text = ""  // Explicitly clear TextInput for security
        error = ""
        entryProgress = 1.0
        passwordMode = false  // Reset to PIN mode
        forceActiveFocus()
        Logger.info("PinScreen", "📱 PIN screen shown")
    }
}
