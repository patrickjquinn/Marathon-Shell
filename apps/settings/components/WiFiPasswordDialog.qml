import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: passwordDialog
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.85)
    visible: false
    z: 1000
    
    property string networkSsid: ""
    property string networkSecurity: ""
    
    signal canceled()
    signal confirmed(string password)
    
    function show(ssid, security) {
        networkSsid = ssid
        networkSecurity = security
        passwordInput.text = ""
        passwordInput.forceActiveFocus()
        visible = true
    }
    
    function hide() {
        visible = false
        passwordInput.text = ""
    }
    
    MouseArea {
        anchors.fill: parent
        onClicked: {
            // Prevent clicks from passing through
        }
    }
    
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 400)
        height: contentColumn.height + 48
        radius: Constants.borderRadiusLarge
        color: MColors.surface
        border.width: 1
        border.color: MColors.borderOuter
        
        Column {
            id: contentColumn
            width: parent.width - 48
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 24
            spacing: Constants.spacingLarge
            
            // Title
            Text {
                width: parent.width
                text: "Connect to WiFi"
                color: MColors.text
                font.pixelSize: MTypography.sizeHeading3
                font.weight: Font.Medium
                font.family: MTypography.fontFamily
            }
            
            // Network name
            Text {
                width: parent.width
                text: networkSsid
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                wrapMode: Text.WordWrap
            }
            
            // Security info
            Text {
                width: parent.width
                text: networkSecurity || "Open Network"
                color: MColors.textTertiary
                font.pixelSize: MTypography.sizeCaption
                font.family: MTypography.fontFamily
            }
            
            // Password input
            Rectangle {
                width: parent.width
                height: 48
                radius: Constants.borderRadiusSmall
                color: MColors.backgroundLight
                border.width: passwordInput.activeFocus ? 2 : 1
                border.color: passwordInput.activeFocus ? MColors.accent : MColors.border
                
                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    anchors.margins: Constants.spacingMedium
                    color: MColors.text
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    echoMode: showPasswordButton.checked ? TextInput.Normal : TextInput.Password
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    
                    Text {
                        anchors.fill: parent
                        text: "Enter password"
                        color: MColors.textTertiary
                        font: parent.font
                        verticalAlignment: parent.verticalAlignment
                        visible: !parent.text && !parent.activeFocus
                    }
                    
                    Keys.onReturnPressed: {
                        if (passwordInput.text.length > 0) {
                            passwordDialog.confirmed(passwordInput.text)
                        }
                    }
                    
                    Keys.onEscapePressed: {
                        passwordDialog.canceled()
                    }
                }
                
                // Show password toggle
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: Constants.spacingSmall
                    width: Constants.touchTargetSmall
                    height: Constants.touchTargetSmall
                    radius: Constants.borderRadiusSmall
                    color: showPasswordButton.checked ? MColors.accent : "transparent"
                    
                    Icon {
                        anchors.centerIn: parent
                        name: showPasswordButton.checked ? "eye-off" : "eye"
                        size: Constants.iconSizeSmall
                        color: showPasswordButton.checked ? MColors.textInverse : MColors.textSecondary
                    }
                    
                    MouseArea {
                        id: showPasswordButton
                        anchors.fill: parent
                        property bool checked: false
                        onClicked: {
                            checked = !checked
                            HapticService.light()
                        }
                    }
                }
            }
            
            // Buttons
            Row {
                width: parent.width
                height: 48
                spacing: Constants.spacingMedium
                
                // Cancel button
                Rectangle {
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: cancelMouseArea.pressed ? MColors.backgroundLight : MColors.background
                    border.width: 1
                    border.color: MColors.border
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: MColors.text
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.Medium
                        font.family: MTypography.fontFamily
                    }
                    
                    MouseArea {
                        id: cancelMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light()
                            passwordDialog.canceled()
                        }
                    }
                }
                
                // Connect button
                Rectangle {
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: connectMouseArea.pressed ? Qt.darker(MColors.accent, 1.2) : MColors.accent
                    opacity: passwordInput.text.length > 0 ? 1.0 : 0.5
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Connect"
                        color: MColors.textInverse
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.Medium
                        font.family: MTypography.fontFamily
                    }
                    
                    MouseArea {
                        id: connectMouseArea
                        anchors.fill: parent
                        enabled: passwordInput.text.length > 0
                        onClicked: {
                            HapticService.medium()
                            passwordDialog.confirmed(passwordInput.text)
                        }
                    }
                }
            }
        }
    }
}

