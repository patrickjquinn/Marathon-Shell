pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: securityPage

    property string pageName: "security"
    property bool showQuickPINDialog: false
    property bool showRemovePINDialog: false
    property string pinError: ""
    property string pendingPINAction: ""

    function closePINDialogs() {
        showQuickPINDialog = false;
        showRemovePINDialog = false;
        pendingPINAction = "";
        pinError = "";
        newPINField.text = "";
        confirmPINField.text = "";
        systemPasswordField.text = "";
        removePasswordField.text = "";
    }

    pageTitle: "Security"
    overlayOpen: showQuickPINDialog || showRemovePINDialog
    onCloseOverlayRequested: closePINDialogs()
    Component.onCompleted: {
        Logger.info("SecurityPage", "Initialized");
    }

    MModal {
        id: quickPINModal

        showing: securityPage.showQuickPINDialog
        title: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Change Quick PIN" : "Set Quick PIN"
        onClosed: securityPage.closePINDialogs()

        content: Column {
            width: parent.width
            spacing: MSpacing.md

            Text {
                width: parent.width
                text: "Quick PIN is a convenience feature. Your system password will always work."
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
            }

            MTextField {
                id: newPINField

                width: parent.width
                label: "New PIN"
                placeholder: "4-6 digits"
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9]{0,6}/
                }
            }

            MTextField {
                id: confirmPINField

                width: parent.width
                label: "Confirm PIN"
                placeholder: "Enter the PIN again"
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9]{0,6}/
                }
                errorText: text.length > 0 && text.length >= newPINField.text.length && text !== newPINField.text ? "PINs don't match" : ""
            }

            MTextField {
                id: systemPasswordField

                width: parent.width
                label: "System password"
                placeholder: "Required to change the PIN"
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            }

            Text {
                width: parent.width
                text: securityPage.pinError
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                color: MColors.error
                wrapMode: Text.WordWrap
                visible: text !== ""
            }

            Row {
                anchors.right: parent.right
                spacing: MSpacing.sm

                MButton {
                    text: "Cancel"
                    variant: "text"
                    onClicked: securityPage.closePINDialogs()
                }

                MButton {
                    text: "Set PIN"
                    variant: "primary"
                    controlState: securityPage.pendingPINAction === "set" ? "loading" : "default"
                    onClicked: {
                        securityPage.pinError = SettingsController.quickPinValidationError(newPINField.text, systemPasswordField.text);
                        if (securityPage.pinError.length === 0 && confirmPINField.text !== newPINField.text)
                            securityPage.pinError = "The PINs don't match. Enter the same PIN in both fields.";
                        if (securityPage.pinError.length > 0)
                            return;
                        securityPage.pendingPINAction = "set";
                        SecurityManagerCpp.setQuickPIN(newPINField.text, systemPasswordField.text);
                    }
                }
            }
        }
    }

    MModal {
        id: removePINModal

        showing: securityPage.showRemovePINDialog
        title: "Remove Quick PIN?"
        onClosed: securityPage.closePINDialogs()

        content: Column {
            width: parent.width
            spacing: MSpacing.md

            Text {
                width: parent.width
                text: "After removing the Quick PIN you'll unlock with your system password. Enter it to confirm."
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
            }

            MTextField {
                id: removePasswordField

                width: parent.width
                label: "System password"
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            }

            Text {
                width: parent.width
                text: securityPage.pinError
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                color: MColors.error
                wrapMode: Text.WordWrap
                visible: text !== ""
            }

            Row {
                anchors.right: parent.right
                spacing: MSpacing.sm

                MButton {
                    text: "Cancel"
                    variant: "text"
                    onClicked: securityPage.closePINDialogs()
                }

                MButton {
                    text: "Remove PIN"
                    variant: "danger"
                    controlState: securityPage.pendingPINAction === "remove" ? "loading" : "default"
                    onClicked: {
                        if (removePasswordField.text.trim().length === 0) {
                            securityPage.pinError = "Enter your system password to remove the PIN.";
                            return;
                        }
                        securityPage.pinError = "";
                        securityPage.pendingPINAction = "remove";
                        SecurityManagerCpp.removeQuickPIN(removePasswordField.text);
                    }
                }
            }
        }
    }

    Connections {
        function onQuickPINChanged() {
            Logger.info("SecurityPage", "Quick PIN changed");
            if (securityPage.pendingPINAction !== "")
                securityPage.closePINDialogs();
        }

        function onAuthenticationFailed(reason) {
            if (securityPage.pendingPINAction === "")
                return;
            securityPage.pendingPINAction = "";
            securityPage.pinError = reason;
        }

        target: SecurityManagerCpp
    }

    content: Flickable {
        contentHeight: securityContent.height + MSpacing.xxl
        clip: true

        Column {
            id: securityContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            MSection {
                title: "Authentication"
                width: parent.width - parent.leftPadding - parent.rightPadding

                MSettingsListItem {
                    title: "Lock Method"
                    subtitle: {
                        return SettingsController.authModeLabel(SecurityManagerCpp ? SecurityManagerCpp.authMode : -1);
                    }
                    iconName: "lock"
                    enabled: false
                }

                MSettingsListItem {
                    title: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Change Quick PIN" : "Set Quick PIN"
                    subtitle: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Update your convenience PIN" : "Set a quick 4-6 digit PIN"
                    iconName: "hash"
                    onSettingClicked: securityPage.showQuickPINDialog = true
                }

                MSettingsListItem {
                    title: "Remove Quick PIN"
                    subtitle: "Use system password only"
                    iconName: "trash-2"
                    visible: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN
                    onSettingClicked: securityPage.showRemovePINDialog = true
                }
            }

            MSection {
                title: "Biometric"
                width: parent.width - parent.leftPadding - parent.rightPadding

                MSettingsListItem {
                    title: "Fingerprint"
                    subtitle: SecurityManagerCpp && SecurityManagerCpp.fingerprintAvailable ? "Enrolled and ready" : "Not enrolled"
                    iconName: "fingerprint"
                }
            }

            MSection {
                title: "Security Status"
                width: parent.width - parent.leftPadding - parent.rightPadding

                MSettingsListItem {
                    title: "Failed Attempts"
                    subtitle: SecurityManagerCpp ? SecurityManagerCpp.failedAttempts.toString() : "0"
                    iconName: "shield-alert"
                    enabled: false
                }

                MSettingsListItem {
                    title: "Account Status"
                    subtitle: {
                        return SettingsController.lockoutStatusText(SecurityManagerCpp ? SecurityManagerCpp.isLockedOut : false, SecurityManagerCpp ? SecurityManagerCpp.lockoutSecondsRemaining : 0);
                    }
                    iconName: SecurityManagerCpp && SecurityManagerCpp.isLockedOut ? "lock" : "check-circle"
                    enabled: false
                }
            }

            MSection {
                title: "How It Works"
                width: parent.width - parent.leftPadding - parent.rightPadding

                Text {
                    width: parent.width
                    text: "Marathon uses your system password (PAM) for secure authentication. " + "Quick PIN is an optional convenience feature stored encrypted. " + "Fingerprint authentication is provided by fprintd."
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                    topPadding: MSpacing.sm
                    leftPadding: MSpacing.md
                    rightPadding: MSpacing.md
                }

                Text {
                    width: parent.width
                    text: "Security features:\n" + "• PAM-based authentication\n" + "• Rate limiting (5 attempts)\n" + "• Exponential lockout\n" + "• Audit logging"
                    font.pixelSize: MTypography.sizeXSmall
                    font.family: MTypography.fontFamily
                    color: MColors.textTertiary
                    wrapMode: Text.WordWrap
                    topPadding: MSpacing.sm
                    bottomPadding: MSpacing.sm
                    leftPadding: MSpacing.md
                    rightPadding: MSpacing.md
                }
            }
        }
    }
}
