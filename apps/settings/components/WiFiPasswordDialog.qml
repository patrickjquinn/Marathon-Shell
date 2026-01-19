pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Item {
    id: wifiDialog

    property string networkSsid: SettingsController.wifiDialogSsid
    property int signalStrength: SettingsController.wifiDialogStrength
    property string securityType: SettingsController.wifiDialogSecurity
    property bool secured: SettingsController.wifiDialogSecured
    property bool isConnecting: SettingsController.wifiDialogConnecting
    property string errorMessage: SettingsController.wifiDialogError
    property bool dialogVisible: SettingsController.wifiDialogVisible
    property bool internalVisible: false

    anchors.fill: parent
    visible: internalVisible
    z: Constants.zIndexModalOverlay + 10
    Keys.onEscapePressed: {
        if (!wifiDialog.isConnecting)
            SettingsController.dismissWifiDialog();
    }
    onDialogVisibleChanged: {
        if (dialogVisible) {
            internalVisible = true;
            passwordInput.text = "";
            if (secured)
                passwordInput.forceActiveFocus();
            showAnimation.restart();
            HapticService.light();
        } else if (internalVisible) {
            hideAnimation.restart();
        }
    }

    Rectangle {
        id: overlay

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!wifiDialog.isConnecting)
                    SettingsController.dismissWifiDialog();
            }
        }
    }

    Rectangle {
        id: dialogCard

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: Math.min(parent.width, Math.round(500 * Constants.scaleFactor))
        height: contentColumn.height + MSpacing.xxl
        radius: Constants.borderRadiusLarge
        color: MColors.surface
        border.width: Constants.borderWidthThin
        border.color: MColors.border
        layer.enabled: true

        Column {
            id: contentColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: MSpacing.lg
            spacing: MSpacing.lg

            Row {
                width: parent.width
                spacing: MSpacing.md

                Rectangle {
                    width: Constants.touchTargetMedium
                    height: Constants.touchTargetMedium
                    radius: Constants.borderRadiusSmall
                    color: Qt.rgba(MColors.marathonTeal.r, MColors.marathonTeal.g, MColors.marathonTeal.b, 0.15)
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        name: wifiDialog.secured ? "lock" : "wifi"
                        size: Constants.iconSizeMedium
                        color: MColors.marathonTeal
                        anchors.centerIn: parent
                        opacity: wifiDialog.signalStrength / 100
                    }
                }

                Column {
                    width: parent.width - Constants.touchTargetMedium - MSpacing.md
                    spacing: MSpacing.xs
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: wifiDialog.networkSsid
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Medium
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Row {
                        spacing: MSpacing.sm

                        Rectangle {
                            width: securityBadgeText.width + Math.round(16 * Constants.scaleFactor)
                            height: Math.round(24 * Constants.scaleFactor)
                            radius: Constants.borderRadiusSmall
                            color: wifiDialog.secured ? Qt.rgba(MColors.warning.r, MColors.warning.g, MColors.warning.b, 0.2) : Qt.rgba(MColors.success.r, MColors.success.g, MColors.success.b, 0.2)

                            Text {
                                id: securityBadgeText

                                text: wifiDialog.secured ? wifiDialog.securityType : "Open"
                                font.pixelSize: MTypography.sizeXSmall
                                font.weight: Font.Medium
                                font.family: MTypography.fontFamily
                                color: wifiDialog.secured ? MColors.warning : MColors.success
                                anchors.centerIn: parent
                            }
                        }

                        Text {
                            text: wifiDialog.signalStrength >= 75 ? "Excellent" : wifiDialog.signalStrength >= 50 ? "Good" : wifiDialog.signalStrength >= 25 ? "Fair" : "Weak"
                            font.pixelSize: MTypography.sizeXSmall
                            font.family: MTypography.fontFamily
                            color: MColors.textTertiary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Constants.inputHeight
                radius: Constants.borderRadiusSmall
                color: MColors.background || Qt.darker(MColors.background, 1.05)
                border.width: passwordInput.activeFocus ? Constants.borderWidthMedium : Constants.borderWidthThin
                border.color: wifiDialog.errorMessage !== "" ? MColors.error : (passwordInput.activeFocus ? MColors.marathonTeal : MColors.border)
                visible: wifiDialog.secured

                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.md
                    spacing: MSpacing.md

                    Icon {
                        name: "key"
                        size: Constants.iconSizeMedium
                        color: passwordInput.activeFocus ? MColors.marathonTeal : MColors.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: passwordInput

                        width: parent.width - Constants.iconSizeMedium - Constants.touchTargetSmall - MSpacing.md * 2
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        echoMode: showPasswordToggle.checked ? TextInput.Normal : TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        enabled: !wifiDialog.isConnecting
                        selectByMouse: true
                        clip: true
                        Keys.onReturnPressed: {
                            if (passwordInput.text.length >= 8)
                                connectButton.clicked();
                        }

                        Text {
                            text: "Enter Password"
                            font.pixelSize: MTypography.sizeBody
                            font.family: MTypography.fontFamily
                            color: MColors.textSecondary
                            visible: passwordInput.text.length === 0 && !passwordInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                        }
                    }

                    Rectangle {
                        id: showPasswordToggle

                        property bool checked: false

                        width: Constants.touchTargetSmall
                        height: Constants.touchTargetSmall
                        radius: Constants.borderRadiusSmall
                        color: checked ? Qt.rgba(MColors.marathonTeal.r, MColors.marathonTeal.g, MColors.marathonTeal.b, 0.15) : "transparent"
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
                                showPasswordToggle.checked = !showPasswordToggle.checked;
                                HapticService.light();
                            }
                        }
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: errorText.height + MSpacing.md
                radius: Constants.borderRadiusSmall
                color: Qt.rgba(MColors.error.r, MColors.error.g, MColors.error.b, 0.15)
                border.width: Constants.borderWidthThin
                border.color: MColors.error
                visible: wifiDialog.errorMessage !== "" && !wifiDialog.isConnecting

                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.sm
                    spacing: MSpacing.sm

                    Icon {
                        name: "alert-circle"
                        size: Constants.iconSizeSmall
                        color: MColors.error
                        anchors.top: parent.top
                        anchors.topMargin: Math.round(2 * Constants.scaleFactor)
                    }

                    Text {
                        id: errorText

                        text: wifiDialog.errorMessage
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        color: MColors.error
                        wrapMode: Text.WordWrap
                        width: parent.width - Constants.iconSizeSmall - MSpacing.sm
                    }
                }
            }

            Column {
                width: parent.width
                spacing: MSpacing.sm
                visible: wifiDialog.isConnecting

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: MSpacing.md

                    BusyIndicator {
                        width: Constants.iconSizeMedium
                        height: Constants.iconSizeMedium
                        running: wifiDialog.isConnecting
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Connecting to " + wifiDialog.networkSsid + "..."
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Row {
                width: parent.width
                height: Constants.touchTargetMedium
                spacing: MSpacing.md

                Rectangle {
                    width: (parent.width - MSpacing.md) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    opacity: wifiDialog.isConnecting ? 0.5 : 1

                    Text {
                        text: "Cancel"
                        font.pixelSize: MTypography.sizeLarge
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !wifiDialog.isConnecting
                        onClicked: {
                            Logger.info("WiFiDialog", "Cancelled");
                            HapticService.light();
                            SettingsController.dismissWifiDialog();
                        }
                    }
                }

                Rectangle {
                    id: connectButton

                    signal clicked

                    width: (parent.width - MSpacing.md) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: (wifiDialog.secured && passwordInput.text.length < 8) || wifiDialog.isConnecting ? Qt.darker(MColors.marathonTeal, 1.5) : MColors.marathonTeal
                    opacity: (wifiDialog.secured && passwordInput.text.length < 8) || wifiDialog.isConnecting ? 0.5 : 1

                    Text {
                        text: "Connect"
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Medium
                        font.family: MTypography.fontFamily
                        color: MColors.background
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: !wifiDialog.isConnecting && (!wifiDialog.secured || passwordInput.text.length >= 8)
                        onClicked: {
                            Logger.info("WiFiDialog", "Connect clicked for: " + wifiDialog.networkSsid);
                            HapticService.medium();
                            SettingsController.submitWifiPassword(passwordInput.text);
                        }
                    }
                }
            }

            Text {
                text: wifiDialog.secured ? "Password must be at least 8 characters" : "This network is not secured"
                font.pixelSize: MTypography.sizeXSmall
                font.family: MTypography.fontFamily
                color: MColors.textTertiary
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !wifiDialog.isConnecting
            }
        }

        transform: Translate {
            id: translateTransform

            y: dialogCard.height
        }

        layer.effect: ShaderEffect {
            property real blur: 32
        }
    }

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
                wifiDialog.internalVisible = false;
                passwordInput.text = "";
            }
        }
    }
}
