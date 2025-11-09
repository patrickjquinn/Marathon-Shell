import QtQuick
import QtQuick.Layouts
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Modals
import MarathonOS.Shell

MPage {
    id: securityPage
    title: "Security"
    
    signal navigateBack()
    
    property bool showQuickPINDialog: false
    property bool showRemovePINDialog: false
    
    content: MScrollView {
        anchors.fill: parent
        contentWidth: parent.width
        
        ColumnLayout {
            width: parent.width
            spacing: 0
            
            // Authentication Method Section
            MSection {
                Layout.fillWidth: true
                title: "Authentication"
                
                MSettingsListItem {
                    title: "Lock Method"
                    subtitle: {
                        if (!SecurityManagerCpp) return "System Password"
                        
                        switch (SecurityManagerCpp.authMode) {
                            case 0: return "System Password (PAM)"
                            case 1: return "Quick PIN"
                            case 2: return "Fingerprint Only"
                            case 3: return "Fingerprint + PIN"
                            default: return "Unknown"
                        }
                    }
                    iconName: "lock"
                    enabled: false
                }
                
                MSettingsListItem {
                    title: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Change Quick PIN" : "Set Quick PIN"
                    subtitle: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? 
                             "Update your convenience PIN" : 
                             "Set a quick 4-6 digit PIN"
                    iconName: "hash"
                    onClicked: showQuickPINDialog = true
                }
                
                MSettingsListItem {
                    title: "Remove Quick PIN"
                    subtitle: "Use system password only"
                    iconName: "trash-2"
                    visible: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN
                    onClicked: showRemovePINDialog = true
                }
            }
            
            // Biometric Section
            MSection {
                Layout.fillWidth: true
                title: "Biometric"
                
                MSettingsListItem {
                    title: "Fingerprint"
                    subtitle: SecurityManagerCpp && SecurityManagerCpp.fingerprintAvailable ?
                             "Enrolled and ready" :
                             "Not enrolled"
                    iconName: "fingerprint"
                    onClicked: {
                        // Launch fprintd enrollment
                        Qt.openUrlExternally("fprintd://enroll")
                    }
                }
                
                Text {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    text: "To enroll a fingerprint, run:\nsudo fprintd-enroll " + (SecurityManagerCpp ? SecurityManagerCpp.getCurrentUsername() : "username")
                    font.pixelSize: 12
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                    visible: SecurityManagerCpp && !SecurityManagerCpp.fingerprintAvailable
                }
            }
            
            // Security Status Section
            MSection {
                Layout.fillWidth: true
                title: "Security Status"
                
                MSettingsListItem {
                    title: "Failed Attempts"
                    subtitle: SecurityManagerCpp ? SecurityManagerCpp.failedAttempts.toString() : "0"
                    iconName: "shield-alert"
                    enabled: false
                }
                
                MSettingsListItem {
                    title: "Account Status"
                    subtitle: {
                        if (!SecurityManagerCpp) return "Active"
                        if (SecurityManagerCpp.isLockedOut) {
                            var secs = SecurityManagerCpp.lockoutSecondsRemaining
                            return "Locked (" + secs + "s remaining)"
                        }
                        return "Active"
                    }
                    iconName: SecurityManagerCpp && SecurityManagerCpp.isLockedOut ? "lock" : "unlock"
                    enabled: false
                }
            }
            
            // Information Section
            MSection {
                Layout.fillWidth: true
                title: "How It Works"
                
                Text {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    text: "Marathon uses your system password (PAM) for secure authentication. " +
                          "Quick PIN is an optional convenience feature stored encrypted. " +
                          "Fingerprint authentication is provided by fprintd."
                    font.pixelSize: 14
                    color: MColors.textSecondary
                    wrapMode: Text.WordWrap
                }
                
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 16
                    text: "Security features:\n" +
                          "• PAM-based authentication\n" +
                          "• Rate limiting (5 attempts)\n" +
                          "• Exponential lockout\n" +
                          "• Audit logging"
                    font.pixelSize: 12
                    color: MColors.textTertiary
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
    
    // Quick PIN Setup Dialog
    MModal {
        id: quickPINModal
        showing: showQuickPINDialog
        title: SecurityManagerCpp && SecurityManagerCpp.hasQuickPIN ? "Change Quick PIN" : "Set Quick PIN"
        
        onClosed: {
            showQuickPINDialog = false
        }
        
        content: Column {
            width: parent.width
            spacing: 16
            
            Text {
                width: parent.width
                text: "Quick PIN is a convenience feature. Your system password will always work."
                font.pixelSize: 14
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
            }
            
            // PIN input
            Rectangle {
                width: parent.width
                height: 48
                color: MColors.bb10Surface
                radius: 8
                border.width: 1
                border.color: newPINField.activeFocus ? MColors.marathonTeal : MColors.borderSubtle
                
                TextInput {
                    id: newPINField
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 16
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
            
            // System password input
            Rectangle {
                width: parent.width
                height: 48
                color: MColors.bb10Surface
                radius: 8
                border.width: 1
                border.color: systemPasswordField.activeFocus ? MColors.marathonTeal : MColors.borderSubtle
                
                TextInput {
                    id: systemPasswordField
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 16
                    font.family: MTypography.fontFamily
                    color: MColors.textPrimary
                    echoMode: TextInput.Password
                    
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
                font.pixelSize: 12
                color: MColors.error
                wrapMode: Text.WordWrap
                visible: text !== ""
            }
            
            Row {
                anchors.right: parent.right
                spacing: 8
                
                MButton {
                    text: "Cancel"
                    variant: "text"
                    onClicked: {
                        showQuickPINDialog = false
                        newPINField.text = ""
                        systemPasswordField.text = ""
                        pinErrorText.text = ""
                    }
                }
                
                MButton {
                    text: "Set PIN"
                    onClicked: {
                        if (newPINField.text.length < 4) {
                            pinErrorText.text = "PIN must be 4-6 digits"
                            return
                        }
                        
                        if (systemPasswordField.text.trim().length === 0) {
                            pinErrorText.text = "System password required"
                            return
                        }
                        
                        // Set Quick PIN via SecurityManager
                        SecurityManagerCpp.setQuickPIN(newPINField.text, systemPasswordField.text)
                        
                        // Dialog will close on success via signal
                        showQuickPINDialog = false
                        newPINField.text = ""
                        systemPasswordField.text = ""
                        pinErrorText.text = ""
                    }
                }
            }
        }
    }
    
    // Remove PIN Confirmation Dialog
    MConfirmDialog {
        id: removePINDialog
        visible: showRemovePINDialog
        title: "Remove Quick PIN?"
        message: "You will need to enter your system password to unlock. This action requires your system password."
        confirmText: "Remove"
        cancelText: "Cancel"
        
        onConfirmed: {
            // TODO: Need to prompt for system password
            // For now, just show message
            showRemovePINDialog = false
        }
        
        onCancelled: {
            showRemovePINDialog = false
        }
        
        onClosed: {
            showRemovePINDialog = false
        }
    }
    
    // SecurityManager signal handlers
    Connections {
        target: SecurityManagerCpp
        
        function onQuickPINChanged() {
            console.log("Quick PIN changed")
        }
        
        function onAuthenticationFailed(reason) {
            pinErrorText.text = reason
        }
    }
}

