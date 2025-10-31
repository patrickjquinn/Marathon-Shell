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
        width: Math.min(parent.width - Math.round(48 * Constants.scaleFactor), Math.round(400 * Constants.scaleFactor))
        height: contentColumn.height + Math.round(48 * Constants.scaleFactor)
        radius: Constants.borderRadiusLarge
        color: MColors.surface || MColors.background
        border.width: Math.round(Constants.borderWidthThin)
        border.color: MColors.borderOuter || MColors.border
        
        Column {
            id: contentColumn
            width: parent.width - Math.round(48 * Constants.scaleFactor)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(24 * Constants.scaleFactor)
            spacing: Constants.spacingLarge
            
            // Title
            Text {
                width: parent.width
                text: "Connect to WiFi"
                color: MColors.text
                font.pixelSize: MTypography.sizeLarge
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
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
            }
            
            // Password input
            Rectangle {
                width: parent.width
                height: Math.round(48 * Constants.scaleFactor)
                radius: Constants.borderRadiusSmall
                color: MColors.backgroundLight || Qt.darker(MColors.background, 1.05)
                border.width: passwordInput.activeFocus ? Math.round(2 * Constants.scaleFactor) : Math.round(Constants.borderWidthThin)
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
                height: Math.round(48 * Constants.scaleFactor)
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
                        color: MColors.text
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

