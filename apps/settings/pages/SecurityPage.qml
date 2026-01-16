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

    pageTitle: "Security"
    Component.onCompleted: {
        Logger.info("SecurityPage", "Initialized");
    }

    MModal {
        id: quickPINModal

        showing: showQuickPINDialog
        title: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Change Quick PIN" : "Set Quick PIN"
        onClosed: {
            showQuickPINDialog = false;
        }

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

            Rectangle {
                width: parent.width
                height: 48
                color: MColors.bb10Surface
                radius: MRadius.md
                border.width: 1
                border.color: newPINField.activeFocus ? MColors.marathonTeal : MColors.borderSubtle

                TextInput {
                    id: newPINField

                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.md
                    anchors.rightMargin: MSpacing.md
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textPrimary
                    echoMode: TextInput.Password
                    maximumLength: 6
                    inputMethodHints: Qt.ImhDigitsOnly

                    Text {
                        text: "Enter 4-6 digit PIN"
                        font: newPINField.font
                        color: MColors.textSecondary
                        visible: newPINField.text.length === 0 && !newPINField.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 48
                color: MColors.bb10Surface
                radius: MRadius.md
                border.width: 1
                border.color: systemPasswordField.activeFocus ? MColors.marathonTeal : MColors.borderSubtle

                TextInput {
                    id: systemPasswordField

                    anchors.fill: parent
                    anchors.leftMargin: MSpacing.md
                    anchors.rightMargin: MSpacing.md
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    color: MColors.textPrimary
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText

                    Text {
                        text: "System password (required)"
                        font: systemPasswordField.font
                        color: MColors.textSecondary
                        visible: systemPasswordField.text.length === 0 && !systemPasswordField.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Text {
                id: pinErrorText

                width: parent.width
                text: ""
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
                    onClicked: {
                        showQuickPINDialog = false;
                        newPINField.text = "";
                        systemPasswordField.text = "";
                        pinErrorText.text = "";
                    }
                }

                MButton {
                    text: "Set PIN"
                    onClicked: {
                        if (newPINField.text.length < 4) {
                            pinErrorText.text = "PIN must be 4-6 digits";
                            return;
                        }
                        if (systemPasswordField.text.trim().length === 0) {
                            pinErrorText.text = "System password required";
                            return;
                        }
                        SecurityManagerCpp.setQuickPIN(newPINField.text, systemPasswordField.text);
                        showQuickPINDialog = false;
                        newPINField.text = "";
                        systemPasswordField.text = "";
                        pinErrorText.text = "";
                    }
                }
            }
        }
    }

    MConfirmDialog {
        id: removePINDialog

        showing: showRemovePINDialog
        title: "Remove Quick PIN?"
        message: "You will need to enter your system password to unlock. This action requires your system password."
        confirmText: "Remove"
        cancelText: "Cancel"
        onConfirmed: {
            showRemovePINDialog = false;
        }
        onCancelled: {
            showRemovePINDialog = false;
        }
    }

    Connections {
        function onQuickPINChanged() {
            Logger.info("SecurityPage", "Quick PIN changed");
        }

        function onAuthenticationFailed(reason) {
            pinErrorText.text = reason;
        }

        target: SecurityManagerCpp
    }

    content: Flickable {
        contentHeight: securityContent.height + 40
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
                        if (!SecurityManagerCpp)
                            return "System Password";

                        switch (SecurityManagerCpp.authMode) {
                        case 0:
                            return "System Password (PAM)";
                        case 1:
                            return "Quick PIN";
                        case 2:
                            return "Fingerprint Only";
                        case 3:
                            return "Fingerprint + PIN";
                        default:
                            return "Unknown";
                        }
                    }
                    iconName: "lock"
                    enabled: false
                }

                MSettingsListItem {
                    title: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Change Quick PIN" : "Set Quick PIN"
                    subtitle: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Update your convenience PIN" : "Set a quick 4-6 digit PIN"
                    iconName: "hash"
                    onSettingClicked: showQuickPINDialog = true
                }

                MSettingsListItem {
                    title: "Remove Quick PIN"
                    subtitle: "Use system password only"
                    iconName: "trash-2"
                    visible: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN
                    onSettingClicked: showRemovePINDialog = true
                }
            }

            MSection {
                title: "Biometric"
                width: parent.width - parent.leftPadding - parent.rightPadding

                MSettingsListItem {
                    title: "Fingerprint"
                    subtitle: SecurityManagerCpp && SecurityManagerCpp.fingerprintAvailable ? "Enrolled and ready" : "Not enrolled"
                    iconName: "fingerprint"
                    onSettingClicked: {
                        Qt.openUrlExternally("fprintd://enroll");
                    }
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
                        if (!SecurityManagerCpp)
                            return "Active";

                        if (SecurityManagerCpp.isLockedOut) {
                            var secs = SecurityManagerCpp.lockoutSecondsRemaining;
                            return "Locked (" + secs + "s remaining)";
                        }
                        return "Active";
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
