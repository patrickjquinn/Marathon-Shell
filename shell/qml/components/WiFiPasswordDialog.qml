import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Controls

/**
 * Polished WiFi Password Dialog
 * 
 * Slide-up modal for entering WiFi passwords with:
 * - Auto-focus on input field
 * - Show/hide password toggle
 * - Signal strength indicator
 * - Security type badge
 * - Loading state during connection
 * - Error handling with retry
 */
Item {
    id: wifiDialog
    anchors.fill: parent
    visible: false
    z: Constants.zIndexModalOverlay + 10

    // Public API
    property string networkSsid: ""
    property int signalStrength: 0
    property string securityType: ""
    property bool secured: true
    property bool isConnecting: false
    property string errorMessage: ""

    signal connectRequested(string password)
    signal cancelled()

    // Show the dialog
    function show(ssid, strength, security, isSecured) {
        networkSsid = ssid
        signalStrength = strength
        securityType = security || "WPA2"
        secured = isSecured
        isConnecting = false
        errorMessage = ""
        passwordInput.text = ""
        passwordInput.forceActiveFocus()
        wifiDialog.visible = true
        showAnimation.start()
        HapticService.light()
        Logger.info("WiFiDialog", "Showing dialog for: " + ssid)
    }

    // Hide the dialog
    function hide() {
        hideAnimation.start()
    }

    // Show error
    function showError(message) {
        errorMessage = message
        isConnecting = false
        HapticService.medium()
    }

    // Show connecting state
    function showConnecting() {
        isConnecting = true
        errorMessage = ""
    }

    // Background overlay
    Rectangle {
        id: overlay
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!isConnecting) {
                    wifiDialog.hide()
                }
            }
        }
    }

    // Dialog card
    Rectangle {
        id: dialogCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: Math.min(parent.width, Math.round(500 * Constants.scaleFactor))
        height: contentColumn.height + Constants.spacingXXLarge
        radius: Constants.borderRadiusLarge
        color: MColors.surface
        border.width: Constants.borderWidthThin
        border.color: MColors.borderOuter
        transform: Translate { id: translateTransform; y: dialogCard.height }

        // Glass morphism effect
        layer.enabled: true
        layer.effect: ShaderEffect {
            property real blur: 32
        }

        Column {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Constants.spacingLarge
            spacing: Constants.spacingLarge

            // Header row
            Row {
                width: parent.width
                spacing: Constants.spacingMedium

                // Network icon with signal strength
                Rectangle {
                    width: Constants.touchTargetMedium
                    height: Constants.touchTargetMedium
                    radius: Constants.borderRadiusSmall
                    color: Qt.rgba(MColors.accent.r, MColors.accent.g, MColors.accent.b, 0.15)
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        name: secured ? "lock" : "wifi"
                        size: Constants.iconSizeMedium
                        color: MColors.accent
                        anchors.centerIn: parent
                        opacity: signalStrength / 100
                    }
                }

                // Network info
                Column {
                    width: parent.width - Constants.touchTargetMedium - Constants.spacingMedium
                    spacing: Constants.spacingXSmall
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: networkSsid
                        font.pixelSize: Typography.sizeLarge
                        font.weight: Font.Medium
                        font.family: Typography.fontFamily
                        color: MColors.textPrimary
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Row {
                        spacing: Constants.spacingSmall

                        // Security badge
                        Rectangle {
                            width: securityBadgeText.width + Math.round(16 * Constants.scaleFactor)
                            height: Math.round(24 * Constants.scaleFactor)
                            radius: Constants.borderRadiusSmall
                            color: secured ? Qt.rgba(MColors.warning.r, MColors.warning.g, MColors.warning.b, 0.2) : Qt.rgba(MColors.success.r, MColors.success.g, MColors.success.b, 0.2)

                            Text {
                                id: securityBadgeText
                                text: secured ? securityType : "Open"
                                font.pixelSize: Typography.sizeXSmall
                                font.weight: Font.Medium
                                font.family: Typography.fontFamily
                                color: secured ? MColors.warning : MColors.success
                                anchors.centerIn: parent
                            }
                        }

                        // Signal strength text
                        Text {
                            text: signalStrength >= 75 ? "Excellent" : signalStrength >= 50 ? "Good" : signalStrength >= 25 ? "Fair" : "Weak"
                            font.pixelSize: Typography.sizeXSmall
                            font.family: Typography.fontFamily
                            color: MColors.textTertiary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // Password input
            Rectangle {
                width: parent.width
                height: Constants.inputHeight
                radius: Constants.borderRadiusSmall
                color: MColors.backgroundLight || Qt.darker(MColors.background, 1.05)
                border.width: passwordInput.activeFocus ? Constants.borderWidthMedium : Constants.borderWidthThin
                border.color: errorMessage !== "" ? MColors.error : (passwordInput.activeFocus ? MColors.accent : MColors.border)
                visible: secured

                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Constants.spacingMedium
                    spacing: Constants.spacingMedium

                    Icon {
                        name: "key"
                        size: Constants.iconSizeMedium
                        color: passwordInput.activeFocus ? MColors.accent : MColors.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: passwordInput
                        width: parent.width - Constants.iconSizeMedium - Constants.touchTargetSmall - Constants.spacingMedium * 2
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Typography.sizeBody
                        font.family: Typography.fontFamily
                        color: MColors.textPrimary
                        echoMode: showPasswordToggle.checked ? TextInput.Normal : TextInput.Password
                        enabled: !isConnecting
                        selectByMouse: true
                        clip: true

                        // Placeholder text (TextInput doesn't render placeholderText, so we fake it)
                        Text {
                            text: "Enter password"
                            font: passwordInput.font
                            color: MColors.textTertiary
                            visible: passwordInput.text.length === 0 && !passwordInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Keys.onReturnPressed: {
                            if (passwordInput.text.length >= 8) {
                                connectButton.clicked()
                            }
                        }
                    }

                    // Show/hide password toggle
                    Rectangle {
                        id: showPasswordToggle
                        property bool checked: false
                        width: Constants.touchTargetSmall
                        height: Constants.touchTargetSmall
                        radius: Constants.borderRadiusSmall
                        color: checked ? Qt.rgba(MColors.accent.r, MColors.accent.g, MColors.accent.b, 0.15) : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            name: showPasswordToggle.checked ? "eye-off" : "eye"
                            size: Constants.iconSizeSmall
                            color: MColors.textSecondary
                            anchors.centerIn: parent
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                showPasswordToggle.checked = !showPasswordToggle.checked
                                HapticService.light()
                            }
                        }
                    }
                }
            }

            // Error message
            Rectangle {
                width: parent.width
                height: errorText.height + Constants.spacingMedium
                radius: Constants.borderRadiusSmall
                color: Qt.rgba(MColors.error.r, MColors.error.g, MColors.error.b, 0.15)
                border.width: Constants.borderWidthThin
                border.color: MColors.error
                visible: errorMessage !== "" && !isConnecting

                Row {
                    anchors.fill: parent
                    anchors.margins: Constants.spacingSmall
                    spacing: Constants.spacingSmall

                    Icon {
                        name: "alert-circle"
                        size: Constants.iconSizeSmall
                        color: MColors.error
                        anchors.top: parent.top
                        anchors.topMargin: Math.round(2 * Constants.scaleFactor)
                    }

                    Text {
                        id: errorText
                        text: errorMessage
                        font.pixelSize: Typography.sizeSmall
                        font.family: Typography.fontFamily
                        color: MColors.error
                        wrapMode: Text.WordWrap
                        width: parent.width - Constants.iconSizeSmall - Constants.spacingSmall
                    }
                }
            }

            // Connection progress
            Column {
                width: parent.width
                spacing: Constants.spacingSmall
                visible: isConnecting

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Constants.spacingMedium

                    BusyIndicator {
                        width: Constants.iconSizeMedium
                        height: Constants.iconSizeMedium
                        running: isConnecting
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Connecting to " + networkSsid + "..."
                        font.pixelSize: Typography.sizeBody
                        font.family: Typography.fontFamily
                        color: MColors.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Action buttons
            Row {
                width: parent.width
                height: Constants.touchTargetMedium
                spacing: Constants.spacingMedium

                // Cancel button
                Rectangle {
                    width: (parent.width - Constants.spacingMedium) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    opacity: isConnecting ? 0.5 : 1.0

                    Text {
                        text: "Cancel"
                        font.pixelSize: Typography.sizeLarge
                        font.family: Typography.fontFamily
                        color: MColors.textPrimary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !isConnecting
                        onClicked: {
                            Logger.info("WiFiDialog", "Cancelled")
                            HapticService.light()
                            wifiDialog.cancelled()
                            wifiDialog.hide()
                        }
                    }
                }

                // Connect button
                Rectangle {
                    id: connectButton
                    width: (parent.width - Constants.spacingMedium) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: (secured && passwordInput.text.length < 8) || isConnecting ? Qt.darker(MColors.accent, 1.5) : MColors.accent
                    opacity: (secured && passwordInput.text.length < 8) || isConnecting ? 0.5 : 1.0

                    signal clicked()

                    Text {
                        text: "Connect"
                        font.pixelSize: Typography.sizeLarge
                        font.weight: Font.Medium
                        font.family: Typography.fontFamily
                        color: MColors.background
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !isConnecting && (!secured || passwordInput.text.length >= 8)
                        onClicked: {
                            Logger.info("WiFiDialog", "Connect clicked for: " + networkSsid)
                            HapticService.medium()
                            wifiDialog.showConnecting()
                            wifiDialog.connectRequested(passwordInput.text)
                        }
                    }
                }
            }

            // Help text
            Text {
                text: secured ? "Password must be at least 8 characters" : "This network is not secured"
                font.pixelSize: Typography.sizeXSmall
                font.family: Typography.fontFamily
                color: MColors.textTertiary
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !isConnecting
            }
        }
    }

    // Show animation
    ParallelAnimation {
        id: showAnimation

        NumberAnimation {
            target: overlay
            property: "opacity"
            from: 0
            to: 1
            duration: 250
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: translateTransform
            property: "y"
            from: dialogCard.height
            to: 0
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    // Hide animation
    SequentialAnimation {
        id: hideAnimation

        ParallelAnimation {
            NumberAnimation {
                target: overlay
                property: "opacity"
                to: 0
                duration: 200
                easing.type: Easing.InQuad
            }

            NumberAnimation {
                target: translateTransform
                property: "y"
                to: dialogCard.height
                duration: 250
                easing.type: Easing.InCubic
            }
        }

        ScriptAction {
            script: {
                wifiDialog.visible = false
                passwordInput.text = ""
                errorMessage = ""
                isConnecting = false
            }
        }
    }

    // Handle back button/escape key
    Keys.onEscapePressed: {
        if (!isConnecting) {
            wifiDialog.hide()
        }
    }
}

