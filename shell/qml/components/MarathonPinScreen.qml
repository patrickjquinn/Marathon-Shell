pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: pinScreen

    property string pin: ""
    property string password: ""
    property string error: ""
    property real entryProgress: 0
    property bool passwordMode: false
    property bool authenticating: false
    // The sensor listens on its own while locked (MarathonShell); this says
    // so, or why the PIN is needed instead, in the error line while it is free.
    readonly property string fingerprintHint: !Security.fingerprintAvailable || passwordMode ? "" : Security.fingerprintBlocked === "restart" ? qsTr("Your PIN is needed after a restart") : Security.fingerprintBlocked === "attempts" ? qsTr("Too many fingerprint attempts") : qsTr("Or touch the fingerprint sensor")
    // What the sensor last asked for, for a moment.
    property string sensorPrompt: ""

    // Compact layout for short/square screens (e.g. HyperPixel 4.0 Square
    // 720×720 on the Hackberry CM5). The DS-canvas (390×844) keypad with
    // 70 px buttons overflows the vertical axis when scaleFactor is driven
    // by physical DPI (≈1.6×) on a screen that's only 720 px tall. Detect
    // via Constants.isSquareScreen + a height-based fallback and shrink
    // the keypad to fit.
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800
    // Compact sizes target real screen pixels: the scale factor on these
    // screens varies with how the panel's size is reported.
    readonly property real compactUnit: Constants.screenHeight / 720 / Constants.scaleFactor
    readonly property real keyButtonSize: compactLayout ? Math.round(72 * compactUnit) : 64
    readonly property real keyCellPadding: compactLayout ? 6 * compactUnit : 12
    readonly property real keypadRowSpacing: compactLayout ? 6 * compactUnit : 12
    readonly property real keypadColumnSpacing: compactLayout ? 14 * compactUnit : 16
    readonly property real columnSpacing: compactLayout ? 8 * compactUnit : 24

    signal pinCorrect
    signal cancelled

    // A word to tap, hugging its text, as Silica's text buttons read.
    component FooterAction: MouseArea {
        id: action

        property alias text: label.text
        property color color

        width: label.implicitWidth + 2 * Silica.Theme.paddingLarge
        height: Silica.Theme.itemSizeSmall
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: clicked(null)

        Silica.Label {
            id: label

            anchors.centerIn: parent
            color: action.pressed ? Silica.Theme.highlightColor : action.color
        }
    }

    function handleInput(digit) {
        if (pin.length < 6 && !Security.isLockedOut) {
            pin += digit;
            error = "";
            if (pin.length === 6)
                verifyTimer.start();
        }
    }

    // A quick PIN is 4-6 digits; only the 6th submits by itself.
    function submitPin() {
        if (pin.length < 4)
            return;
        verifyTimer.stop();
        verifyPin();
    }

    function verifyPin() {
        if (authenticating)
            return;
        if (Security.isLockedOut) {
            var secs = Security.lockoutSecondsRemaining;
            error = qsTr("Locked for %1s").arg(secs);
            HapticManager.heavy();
            return;
        }
        Logger.info("PinScreen", "Starting authentication, showing spinner");
        authenticating = true;
        if (Security.hasQuickPIN && !passwordMode) {
            Security.authenticateQuickPIN(pin);
        } else {
            var inputPassword = passwordMode ? password : pin;
            Security.authenticatePassword(inputPassword);
        }
    }

    function verifyPasswordInput() {
        if (Security.isLockedOut) {
            var secs = Security.lockoutSecondsRemaining;
            error = qsTr("Locked for %1s").arg(secs);
            HapticManager.heavy();
            return;
        }
        if (password.trim().length === 0) {
            error = qsTr("Password cannot be empty");
            HapticManager.light();
            return;
        }
        Logger.info("PinScreen", "Starting password authentication, showing spinner");
        authenticating = true;
        Security.authenticatePassword(password);
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
        sensorPrompt = "";
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
        Logger.info("PinScreen", "PIN screen shown");
    }

    anchors.fill: parent
    // layer.enabled was true (+ smooth) — same as MarathonLockScreen this
    // turned the whole PIN screen into one FBO, and every tap on a digit
    // triggered three Behaviors (dot color, dot scale, button spring)
    // which forced a full re-rasterization every frame. User-perceived
    // delay between tapping a digit and the circle filling. Drop the
    // layer; dirty-region rendering is sufficient.
    layer.enabled: false
    onVisibleChanged: {
        if (visible) {
            SessionStore.isOnLockScreen = true;
            Logger.info("PinScreen", "PIN screen visible - showing lock icon in status bar");
        } else {
            SessionStore.isOnLockScreen = false;
            Logger.info("PinScreen", "PIN screen hidden - showing clock in status bar");
        }
    }
    // A BlackBerry keyboard's number keys type their digit here without Alt.
    readonly property var numberKeys: ({
            [Qt.Key_W]: "1",
            [Qt.Key_E]: "2",
            [Qt.Key_R]: "3",
            [Qt.Key_S]: "4",
            [Qt.Key_D]: "5",
            [Qt.Key_F]: "6",
            [Qt.Key_Z]: "7",
            [Qt.Key_X]: "8",
            [Qt.Key_C]: "9"
        })
    Keys.onPressed: function (event) {
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            handleInput(String.fromCharCode(event.key));
            event.accepted = true;
        } else if (numberKeys[event.key] !== undefined) {
            handleInput(numberKeys[event.key]);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            submitPin();
            event.accepted = true;
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            pin = pin.slice(0, -1);
            error = "";
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            cancelled();
            event.accepted = true;
        }
    }
    focus: visible && entryProgress >= 1

    Connections {
        function onAuthenticationSuccess() {
            Logger.info("PinScreen", " Authentication successful, hiding spinner");
            pinScreen.authenticating = false;
            HapticManager.medium();
            pinScreen.pin = "";
            pinScreen.password = "";
            passwordTextInput.text = "";
            SessionStore.triggerUnlockAnimation();
            unlockDelayTimer.start();
        }

        function onAuthenticationFailed(reason) {
            Logger.warn("PinScreen", " Authentication failed, hiding spinner:", reason);
            pinScreen.authenticating = false;
            HapticManager.heavy();
            pinScreen.pin = "";
            pinScreen.error = reason;
            SessionStore.triggerShakeAnimation();
        }

        function onBiometricPrompt(message) {
            pinScreen.sensorPrompt = message;
            sensorPromptTimer.restart();
        }

        function onFingerprintMismatch(message) {
            HapticManager.heavy();
            pinScreen.error = message;
        }

        function onLockoutStateChanged() {
            if (Security.isLockedOut) {
                var secs = Security.lockoutSecondsRemaining;
                pinScreen.error = qsTr("Locked for %1s").arg(secs);
                Logger.warn("PinScreen", "Account locked for", secs, "seconds");
            } else {
                pinScreen.error = "";
            }
        }

        target: Security
    }

    // The ambience behind the lock code: the same cached, toned image the
    // apps draw on, not a blur of the wallpaper made for this screen.
    KeelAmbienceBackground {
        anchors.fill: parent
        z: 0
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
        brightest: AmbienceService.brightest
        darkest: AmbienceService.darkest
    }

    Column {
        anchors.centerIn: parent
        // Rises into place as the pad fades in.
        scale: 0.94 + 0.06 * pinScreen.opacity
        anchors.verticalCenterOffset: pinScreen.compactLayout ? Math.round((Constants.statusBarHeight - Constants.navBarHeight - footer.height) / 2) : Math.round(-20 * Constants.scaleFactor)
        spacing: Math.round(pinScreen.columnSpacing * Constants.scaleFactor)
        z: 100
        // layer.enabled removed — see note at the root pinScreen Item.
        layer.enabled: false

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(16 * Constants.scaleFactor)

            Text {
                objectName: "pinTitle"
                anchors.horizontalCenter: parent.horizontalCenter
                text: pinScreen.passwordMode ? qsTr("Enter password") : qsTr("Enter PIN")
                color: Silica.Theme.highlightColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeLarge
                renderType: Text.QtRendering
            }
        }

        // The code field: a dot per digit, backspace at its end.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            // Six dots centred, clear of a key-sized cell either side.
            width: Math.max(keypad.width, Math.round((6 * 14 + 5 * 16 + 2 * (pinScreen.keyButtonSize + pinScreen.keyCellPadding)) * Constants.scaleFactor))
            height: Math.round(pinScreen.keyButtonSize * (pinScreen.compactLayout ? 0.7 : 1) * Constants.scaleFactor)

            Row {
                id: pinCircles

                anchors.centerIn: parent
                spacing: Math.round(16 * Constants.scaleFactor)

                Accessible.role: Accessible.StaticText
                Accessible.name: pinScreen.pin.length + " digits entered"

                Repeater {
                    model: pinScreen.pin.length

                    Rectangle {
                        width: Math.round(14 * Constants.scaleFactor)
                        height: Math.round(14 * Constants.scaleFactor)
                        radius: Math.round(7 * Constants.scaleFactor)
                        color: Silica.Theme.highlightColor
                        antialiasing: true
                    }
                }
            }

            Silica.BusyIndicator {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: Silica.BusyIndicatorSize.Small
                running: pinScreen.authenticating && !pinScreen.passwordMode
                visible: pinScreen.authenticating && !pinScreen.passwordMode
                opacity: visible ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: MMotion.ms(150)
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MCircularIconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "backspace"
                iconSize: pinScreen.compactLayout ? Math.round(24 * pinScreen.compactUnit) : 24
                buttonSize: pinScreen.keyButtonSize
                variant: "secondary"
                iconColor: MColors.textSecondary
                //: Accessible name of the PIN pad delete key
                a11yName: qsTr("Delete")
                visible: pinScreen.pin.length > 0 && !pinScreen.authenticating
                onClicked: {
                    HapticManager.light();
                    pinScreen.pin = pinScreen.pin.slice(0, -1);
                    pinScreen.error = "";
                }
            }
        }

        // Two lines reserved, so an error never shifts the keypad.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: pinScreen.width - 2 * Silica.Theme.horizontalPageMargin
            height: Math.ceil(errorMetrics.height * 2)
            opacity: errorText.text !== "" ? 1 : 0

            FontMetrics {
                id: errorMetrics

                font: errorText.font
            }

            Text {
                id: errorText

                objectName: "pinMessage"
                anchors.centerIn: parent
                maximumLineCount: 2
                elide: Text.ElideRight
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: pinScreen.error || pinScreen.sensorPrompt || pinScreen.fingerprintHint
                color: pinScreen.error !== "" ? Silica.Theme.errorColor : Silica.Theme.secondaryColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeSmall
                renderType: Text.QtRendering
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.ms(150)
                    easing.type: Easing.OutCubic
                }
            }

            SequentialAnimation on x {
                running: pinScreen.error !== "" && !MMotion.reduceMotion

                NumberAnimation {
                    to: 8
                    duration: MMotion.ms(40)
                }

                NumberAnimation {
                    to: -8
                    duration: MMotion.ms(40)
                }

                NumberAnimation {
                    to: 4
                    duration: MMotion.ms(40)
                }

                NumberAnimation {
                    to: -4
                    duration: MMotion.ms(40)
                }

                NumberAnimation {
                    to: 0
                    duration: MMotion.ms(40)
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(12 * Constants.scaleFactor)
            visible: !pinScreen.passwordMode

            // MCircularIconButton scales `buttonSize` / `iconSize` by
            // Constants.scaleFactor internally. Pass DESIGN px here —
            // pre-scaling caused the button + halo to render at
            // sf × sf (≈ 2.5×) and overflow the cells, producing the
            // overlapping-circles pin-pad bug.
            Grid {
                id: keypad

                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                columnSpacing: Math.round(pinScreen.keypadColumnSpacing * Constants.scaleFactor)
                rowSpacing: Math.round(pinScreen.keypadRowSpacing * Constants.scaleFactor)
                // layer.enabled was true (with layer.smooth) — the FBO
                // pass on top of the over-sized halo turned the overlap
                // into a stack of semi-transparent overlapping rings.
                // Removing the layer keeps the button chrome single-pass.

                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

                    delegate: Item {
                        id: pinKey

                        required property string modelData
                        property string digit: modelData

                        width: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)
                        height: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)

                        MCircularIconButton {
                            objectName: "key" + pinKey.digit
                            anchors.centerIn: parent
                            disabled: Security.isLockedOut
                            text: pinKey.digit
                            // The whole cell and half the gap, so a near miss still lands.
                            hitMargin: (pinKey.width - diameter + Math.min(keypad.columnSpacing, keypad.rowSpacing)) / 2
                            iconSize: pinScreen.compactLayout ? Math.round(28 * pinScreen.compactUnit) : 28
                            buttonSize: pinScreen.keyButtonSize
                            variant: "secondary"
                            textColor: MColors.textPrimary
                            onClicked: {
                                HapticManager.light();
                                pinScreen.handleInput(pinKey.digit);
                            }
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(pinScreen.keypadColumnSpacing * Constants.scaleFactor)

                Item {
                    width: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)
                    height: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)

                    MCircularIconButton {
                        anchors.centerIn: parent
                        iconName: "keyboard"
                        iconSize: pinScreen.compactLayout ? Math.round(24 * pinScreen.compactUnit) : 24
                        buttonSize: pinScreen.keyButtonSize
                        variant: "secondary"
                        visible: !pinScreen.passwordMode
                        onClicked: {
                            HapticManager.light();
                            pinScreen.switchToPasswordMode();
                        }
                    }
                }

                Item {
                    width: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)
                    height: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)

                    MCircularIconButton {
                        objectName: "key0"
                        anchors.centerIn: parent
                        disabled: Security.isLockedOut
                        text: "0"
                        iconSize: pinScreen.compactLayout ? Math.round(28 * pinScreen.compactUnit) : 28
                        buttonSize: pinScreen.keyButtonSize
                        variant: "secondary"
                        textColor: MColors.textPrimary
                        onClicked: {
                            HapticManager.light();
                            pinScreen.handleInput("0");
                        }
                    }
                }

                Item {
                    width: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)
                    height: Math.round(pinScreen.keyButtonSize * Constants.scaleFactor) + Math.round(pinScreen.keyCellPadding * Constants.scaleFactor)

                    MCircularIconButton {
                        objectName: "acceptKey"
                        anchors.centerIn: parent
                        iconName: "check"
                        iconSize: pinScreen.compactLayout ? Math.round(24 * pinScreen.compactUnit) : 24
                        buttonSize: pinScreen.keyButtonSize
                        variant: disabled ? "secondary" : "primary"
                        disabled: pinScreen.pin.length < 4 || pinScreen.authenticating || Security.isLockedOut
                        a11yName: qsTr("Unlock")
                        onClicked: {
                            HapticManager.light();
                            pinScreen.submitPin();
                        }
                    }
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(24 * Constants.scaleFactor)
            visible: pinScreen.passwordMode
            width: Math.round(320 * Constants.scaleFactor)

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(280 * Constants.scaleFactor)
                height: Math.round(52 * Constants.scaleFactor)

                Rectangle {
                    id: passwordField

                    anchors.fill: parent
                    // Silica's field: no box, an underline lit while focused.
                    color: "transparent"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                        color: passwordTextInput.activeFocus ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)
                    }
                    Component.onCompleted: {
                        if (pinScreen.passwordMode)
                            Qt.callLater(function () {
                                passwordTextInput.forceActiveFocus();
                            });
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Enter password")
                        color: Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeMedium
                        font.family: Silica.Theme.fontFamily
                        visible: passwordTextInput.text.length === 0 && !passwordTextInput.activeFocus
                    }

                    TextInput {
                        id: passwordTextInput

                        anchors.fill: parent
                        anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                        anchors.rightMargin: Math.round(48 * Constants.scaleFactor)
                        verticalAlignment: TextInput.AlignVCenter
                        color: Silica.Theme.highlightColor
                        selectedTextColor: Silica.Theme.highlightDimmerColor
                        selectionColor: Silica.Theme.highlightColor
                        font.pixelSize: Silica.Theme.fontSizeMedium
                        font.family: Silica.Theme.fontFamily
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        echoMode: TextInput.Password
                        onAccepted: pinScreen.verifyPasswordInput()
                        onTextChanged: {
                            pinScreen.password = text;
                            pinScreen.error = "";
                        }
                    }
                }

                Silica.BusyIndicator {
                    anchors.right: parent.right
                    anchors.rightMargin: Math.round(12 * Constants.scaleFactor)
                    anchors.verticalCenter: parent.verticalCenter
                    size: Silica.BusyIndicatorSize.Small
                    running: pinScreen.authenticating && pinScreen.passwordMode
                    visible: pinScreen.authenticating && pinScreen.passwordMode
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: MMotion.ms(150)
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                spacing: Math.round(12 * Constants.scaleFactor)

                Silica.Button {
                    width: (parent.width - parent.spacing) / 2
                    text: qsTr("Use PIN")
                    backgroundColor: "transparent"
                    border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, Silica.Theme.opacityFaint)
                    onClicked: pinScreen.switchToPINMode()
                }

                Silica.Button {
                    width: (parent.width - parent.spacing) / 2
                    text: qsTr("Unlock")
                    enabled: !pinScreen.authenticating
                    onClicked: pinScreen.verifyPasswordInput()
                }
            }
        }
    }

    // Apart, at the bottom corners, clear of the keypad.
    Item {
        id: footer

        objectName: "pinFooter"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Silica.Theme.horizontalPageMargin - Silica.Theme.paddingLarge
        anchors.rightMargin: Silica.Theme.horizontalPageMargin - Silica.Theme.paddingLarge
        anchors.bottomMargin: Constants.navBarHeight
        height: cancelButton.height
        z: 100

        FooterAction {
            id: cancelButton

            objectName: "pinCancel"
            anchors.left: parent.left
            //: Button that leaves the PIN screen
            text: qsTr("Cancel")
            color: Silica.Theme.secondaryColor
            onClicked: {
                HapticManager.light();
                pinScreen.cancelled();
            }
        }

        // Emergency dial — required to be reachable from the lock screen
        // without authentication (FCC E911 / EU Article 109). Launches the
        // phone app in --emergency-only mode; the modem itself enforces
        // which numbers are allowed (3GPP TS 22.101 + SIM EF_ECC).
        FooterAction {
            objectName: "pinEmergency"
            anchors.right: parent.right
            text: qsTr("Emergency call")
            visible: typeof Modem === "undefined" || Modem.modemAvailable
            color: Silica.Theme.errorColor
            onClicked: {
                HapticManager.medium();
                Logger.info("PinScreen", "Emergency dial requested from lock screen");
                Tasks.launchAppWithRoute("phone", "/emergency", "{}");
            }
        }
    }

    Timer {
        id: verifyTimer

        interval: 100
        onTriggered: pinScreen.verifyPin()
    }

    Timer {
        id: sensorPromptTimer

        interval: 2500
        onTriggered: pinScreen.sensorPrompt = ""
    }

    Timer {
        id: unlockDelayTimer

        interval: 350
        onTriggered: {
            pinScreen.pinCorrect();
        }
    }
}
