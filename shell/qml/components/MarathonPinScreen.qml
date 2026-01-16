import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Theme
import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects

Item {
    id: pinScreen

    property string pin: ""
    property string password: ""
    property string error: ""
    property real entryProgress: 0
    property bool passwordMode: false
    property bool biometricInProgress: false
    property bool authenticating: false

    signal pinCorrect
    signal cancelled

    function handleInput(digit) {
        if (pin.length < 6) {
            pin += digit;
            error = "";
            if (pin.length === 6)
                verifyTimer.start();
        }
    }

    function verifyPin() {
        if (SecurityManagerCpp.isLockedOut) {
            var secs = SecurityManagerCpp.lockoutSecondsRemaining;
            error = "Locked for " + secs + "s";
            HapticManager.heavy();
            return;
        }
        Logger.info("PinScreen", "🔄 Starting authentication, showing spinner");
        authenticating = true;
        if (SecurityManagerCpp.hasQuickPIN && !passwordMode) {
            SecurityManagerCpp.authenticateQuickPIN(pin);
        } else {
            var inputPassword = passwordMode ? password : pin;
            SecurityManagerCpp.authenticatePassword(inputPassword);
        }
    }

    function verifyPasswordInput() {
        if (SecurityManagerCpp.isLockedOut) {
            var secs = SecurityManagerCpp.lockoutSecondsRemaining;
            error = "Locked for " + secs + "s";
            HapticManager.heavy();
            return;
        }
        if (password.trim().length === 0) {
            error = "Password cannot be empty";
            HapticManager.light();
            return;
        }
        Logger.info("PinScreen", "🔄 Starting password authentication, showing spinner");
        authenticating = true;
        SecurityManagerCpp.authenticatePassword(password);
    }

    function startBiometric() {
        if (SecurityManagerCpp.isLockedOut) {
            var secs = SecurityManagerCpp.lockoutSecondsRemaining;
            error = "Locked for " + secs + "s";
            HapticManager.heavy();
            return;
        }
        if (!SecurityManagerCpp.fingerprintAvailable) {
            error = "Fingerprint not enrolled";
            HapticManager.light();
            return;
        }
        biometricInProgress = true;
        error = "Place your finger...";
        SecurityManagerCpp.authenticateBiometric(0);
    }

    function switchToPasswordMode() {
        passwordMode = true;
        pin = "";
        password = "";
        passwordTextInput.text = "";
        error = "";
        Logger.info("PinScreen", "Switched to password mode");
        Qt.callLater(function () {
            passwordTextInput.forceActiveFocus();
        });
    }

    function switchToPINMode() {
        passwordMode = false;
        pin = "";
        password = "";
        passwordTextInput.text = "";
        error = "";
        Logger.info("PinScreen", "Switched to PIN mode");
    }

    function reset() {
        pin = "";
        password = "";
        passwordTextInput.text = "";
        error = "";
        entryProgress = 0;
    }

    function show() {
        pin = "";
        password = "";
        passwordTextInput.text = "";
        error = "";
        entryProgress = 1;
        passwordMode = false;
        forceActiveFocus();
        Logger.info("PinScreen", "📱 PIN screen shown");
    }

    anchors.fill: parent
    layer.enabled: true
    layer.smooth: true
    onVisibleChanged: {
        if (visible) {
            SessionStore.isOnLockScreen = true;
            Logger.info("PinScreen", "PIN screen visible - showing lock icon in status bar");
        } else {
            SessionStore.isOnLockScreen = false;
            Logger.info("PinScreen", "PIN screen hidden - showing clock in status bar");
        }
    }
    Keys.onPressed: function (event) {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            var digit = String.fromCharCode(event.key);
            handleInput(digit);
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            pin = "";
            error = "";
            event.accepted = true;
        }
    }
    focus: visible && entryProgress >= 1

    Connections {
        function onAuthenticationSuccess() {
            Logger.info("PinScreen", " Authentication successful, hiding spinner");
            authenticating = false;
            HapticManager.medium();
            pin = "";
            password = "";
            passwordTextInput.text = "";
            SessionStore.triggerUnlockAnimation();
            unlockDelayTimer.start();
        }

        function onAuthenticationFailed(reason) {
            Logger.warn("PinScreen", " Authentication failed, hiding spinner:", reason);
            authenticating = false;
            HapticManager.heavy();
            error = reason;
            errorTimer.start();
            biometricInProgress = false;
            SessionStore.triggerShakeAnimation();
        }

        function onBiometricPrompt(message) {
            Logger.info("PinScreen", "👆 Biometric prompt:", message);
            error = message;
        }

        function onLockoutStateChanged() {
            if (SecurityManagerCpp.isLockedOut) {
                var secs = SecurityManagerCpp.lockoutSecondsRemaining;
                error = "Locked for " + secs + "s";
                Logger.warn("PinScreen", "🔒 Account locked for", secs, "seconds");
            }
        }

        target: SecurityManagerCpp
    }

    Image {
        id: wallpaperSource

        anchors.fill: parent
        source: WallpaperStore.path
        fillMode: Image.PreserveAspectCrop
        cache: true
        smooth: true
        z: 0
    }

    Rectangle {
        id: glassRect

        anchors.fill: parent
        color: MColors.background
        opacity: 0.95
        z: 1

        ShaderEffectSource {
            id: wallpaperCapture

            anchors.fill: parent
            sourceItem: wallpaperSource
            sourceRect: Qt.rect(0, 0, width, height)
            visible: false
        }

        MultiEffect {
            anchors.fill: parent
            source: wallpaperCapture
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1
            saturation: 0.3
            brightness: -0.2
        }
    }

    Rectangle {
        anchors.fill: parent
        color: MColors.overlay
        z: 2
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: Math.round(-20 * Constants.scaleFactor)
        spacing: Math.round(24 * Constants.scaleFactor)
        z: 100
        layer.enabled: true
        layer.smooth: true

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(16 * Constants.scaleFactor)

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: passwordMode ? "Enter Password" : "Enter PIN"
                color: MColors.text
                font.pixelSize: Math.round(24 * Constants.scaleFactor)
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

                        PropertyAction {
                            target: parent.children[1]
                            property: "text"
                        }

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

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(16 * Constants.scaleFactor)

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
                        scale: (index === pin.length - 1 && pin.length > 0) ? 1.3 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutBack
                            }
                        }
                    }
                }
            }

            MActivityIndicator {
                anchors.verticalCenter: pinCircles.verticalCenter
                size: Math.round(32 * Constants.scaleFactor)
                color: MColors.accentBright
                running: authenticating && !passwordMode
                visible: authenticating && !passwordMode
                opacity: visible ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(300 * Constants.scaleFactor)
            height: Math.round(40 * Constants.scaleFactor)
            radius: Math.round(8 * Constants.scaleFactor)
            color: Qt.rgba(MColors.error.r, MColors.error.g, MColors.error.b, 0.15)
            visible: error !== ""
            opacity: error !== "" ? 1 : 0

            Text {
                anchors.centerIn: parent
                text: error
                color: MColors.error
                font.pixelSize: Math.round(14 * Constants.scaleFactor)
                font.weight: Font.Medium
                renderType: Text.NativeRendering
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            SequentialAnimation on x {
                running: error !== ""

                NumberAnimation {
                    to: 8
                    duration: 40
                }

                NumberAnimation {
                    to: -8
                    duration: 40
                }

                NumberAnimation {
                    to: 4
                    duration: 40
                }

                NumberAnimation {
                    to: -4
                    duration: 40
                }

                NumberAnimation {
                    to: 0
                    duration: 40
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(12 * Constants.scaleFactor)
            visible: !passwordMode

            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                columnSpacing: Math.round(16 * Constants.scaleFactor)
                rowSpacing: Math.round(12 * Constants.scaleFactor)
                layer.enabled: true
                layer.smooth: true

                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

                    delegate: Item {
                        property string digit: modelData

                        width: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)
                        height: Math.round(70 * Constants.scaleFactor) + Math.round(12 * Constants.scaleFactor)

                        MCircularIconButton {
                            anchors.centerIn: parent
                            text: digit
                            iconSize: Math.round(28 * Constants.scaleFactor)
                            buttonSize: Math.round(70 * Constants.scaleFactor)
                            variant: "secondary"
                            textColor: MColors.textPrimary
                            onClicked: {
                                HapticManager.light();
                                handleInput(parent.digit);
                            }
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(16 * Constants.scaleFactor)

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
                            HapticManager.light();
                            switchToPasswordMode();
                        }
                    }
                }

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
                            HapticManager.light();
                            handleInput("0");
                        }
                    }
                }

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
                            HapticManager.light();
                            pin = "";
                            error = "";
                        }
                    }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(24 * Constants.scaleFactor)
            visible: passwordMode
            width: Math.round(320 * Constants.scaleFactor)

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
                    Component.onCompleted: {
                        if (passwordMode)
                            Qt.callLater(function () {
                                passwordTextInput.forceActiveFocus();
                            });
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
                        anchors.rightMargin: Math.round(48 * Constants.scaleFactor)
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
                            password = text;
                            error = "";
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 200
                        }
                    }
                }

                MActivityIndicator {
                    anchors.right: parent.right
                    anchors.rightMargin: Math.round(12 * Constants.scaleFactor)
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.round(28 * Constants.scaleFactor)
                    color: MColors.accentBright
                    running: authenticating && passwordMode
                    visible: authenticating && passwordMode
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                spacing: Math.round(12 * Constants.scaleFactor)

                MButton {
                    width: (parent.width - parent.spacing) / 2
                    text: "Use PIN"
                    variant: "secondary"
                    onClicked: switchToPINMode()
                }

                MButton {
                    width: (parent.width - parent.spacing) / 2
                    text: "Unlock"
                    variant: "primary"
                    enabled: !authenticating
                    onClicked: verifyPasswordInput()
                }
            }
        }

        MCircularIconButton {
            anchors.horizontalCenter: parent.horizontalCenter
            iconName: "fingerprint"
            iconSize: Math.round(28 * Constants.scaleFactor)
            buttonSize: Math.round(64 * Constants.scaleFactor)
            variant: "secondary"
            visible: SecurityManagerCpp.fingerprintAvailable && !biometricInProgress && !passwordMode
            enabled: !SecurityManagerCpp.isLockedOut
            onClicked: {
                HapticManager.light();
                startBiometric();
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Cancel"
            color: MColors.textSecondary
            font.pixelSize: Math.round(16 * Constants.scaleFactor)
            font.weight: Font.Medium
            opacity: cancelMouseArea.pressed ? 0.5 : 0.8
            renderType: Text.NativeRendering

            MouseArea {
                id: cancelMouseArea

                anchors.fill: parent
                anchors.margins: Math.round(-16 * Constants.scaleFactor)
                onClicked: {
                    HapticManager.light();
                    cancelled();
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 80
                }
            }
        }
    }

    Timer {
        id: verifyTimer

        interval: 100
        onTriggered: verifyPin()
    }

    Timer {
        id: errorTimer

        interval: 1200
        onTriggered: {
            pin = "";
            error = "";
        }
    }

    Timer {
        id: unlockDelayTimer

        interval: 350
        onTriggered: {
            pinCorrect();
        }
    }
}
