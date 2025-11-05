import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Item {
    Flickable {
        anchors.fill: parent
        contentHeight: telephonyColumn.height
        clip: true
        
        Column {
            id: telephonyColumn
            width: parent.width
            spacing: MSpacing.md
            padding: MSpacing.lg
            
            Text {
                text: "📞 Telephony & SMS"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Bold
                color: MColors.textPrimary
            }
            
            MCard {
                width: parent.width - parent.padding * 2
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg
                    
                    Text {
                        text: "Incoming Call Test"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Simulates an incoming phone call"
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Unknown Number"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof TelephonyService !== 'undefined') {
                                    TelephonyService.simulateIncomingCall("+1234567890")
                                    Logger.info("TestApp", "✓ Simulated incoming call")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    Logger.error("TestApp", "✗ TelephonyService not available")
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                        
                        MButton {
                            text: "Known Contact"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof TelephonyService !== 'undefined') {
                                    if (typeof ContactsManager !== 'undefined') {
                                        ContactsManager.addContact("John Doe", "+1555123456", "john@example.com")
                                        Logger.info("TestApp", "✓ Added test contact")
                                    }
                                    TelephonyService.simulateIncomingCall("+1555123456")
                                    Logger.info("TestApp", "✓ Simulated incoming call from contact")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    Logger.error("TestApp", "✗ TelephonyService not available")
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                    }
                }
            }
            
            MCard {
                width: parent.width - parent.padding * 2
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg
                    
                    Text {
                        text: "SMS Test"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Simulates receiving text messages"
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                    
                    Row {
                        spacing: MSpacing.md
                        
                        MButton {
                            text: "Single SMS"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof SMSService !== 'undefined') {
                                    SMSService.simulateIncomingSMS("+1234567890", "Hey! This is a test message from the Marathon Test Suite.")
                                    Logger.info("TestApp", "✓ Simulated incoming SMS")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    Logger.error("TestApp", "✗ SMSService not available")
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                        
                        MButton {
                            text: "Multiple SMS"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof SMSService !== 'undefined') {
                                    for (var i = 0; i < 3; i++) {
                                        SMSService.simulateIncomingSMS("+1555987654" + i, "Message " + (i + 1) + " from test suite")
                                    }
                                    Logger.info("TestApp", "✓ Simulated 3 incoming SMS")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    Logger.error("TestApp", "✗ SMSService not available")
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                    }
                }
            }
            
            MCard {
                width: parent.width - parent.padding * 2
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    padding: MSpacing.lg
                    
                    Text {
                        text: "Call State Tests"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    Text {
                        text: "Test different call states and transitions"
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                    
                    Flow {
                        width: parent.width
                        spacing: MSpacing.sm
                        
                        MButton {
                            text: "Active Call"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof TelephonyService !== 'undefined') {
                                    TelephonyService.simulateCallStateChange("active")
                                    Logger.info("TestApp", "✓ Call state: active")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                        
                        MButton {
                            text: "Ringing"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof TelephonyService !== 'undefined') {
                                    TelephonyService.simulateCallStateChange("ringing")
                                    Logger.info("TestApp", "✓ Call state: ringing")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                        
                        MButton {
                            text: "End Call"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof TelephonyService !== 'undefined') {
                                    TelephonyService.simulateCallStateChange("idle")
                                    Logger.info("TestApp", "✓ Call state: idle")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                        
                        MButton {
                            text: "Missed Call"
                            variant: "secondary"
                            onClicked: {
                                HapticService.light()
                                if (typeof TelephonyService !== 'undefined') {
                                    TelephonyService.simulateIncomingCall("+1555111222")
                                    Qt.callLater(function() {
                                        TelephonyService.simulateCallStateChange("terminated")
                                    })
                                    Logger.info("TestApp", "✓ Simulated missed call")
                                    if (testApp) { testApp.passedTests++; testApp.totalTests++; }
                                } else {
                                    if (testApp) { testApp.failedTests++; testApp.totalTests++; }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

