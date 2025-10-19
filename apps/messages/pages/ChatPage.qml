import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    color: MColors.background
    
    property var conversation
    property var messages: typeof SMSService !== 'undefined' && conversation ? SMSService.getMessages(conversation.id) : []
    
    Component.onCompleted: {
        if (typeof SMSService !== 'undefined' && conversation) {
            messages = SMSService.getMessages(conversation.id)
            SMSService.markAsRead(conversation.id)
        }
    }
    
    Connections {
        target: typeof SMSService !== 'undefined' ? SMSService : null
        function onMessageSent(recipient, timestamp) {
            if (conversation && messages) {
                messages = SMSService.getMessages(conversation.id)
            }
        }
    }
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Rectangle {
            width: parent.width
            height: Constants.actionBarHeight
            color: MColors.surface
            
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }
            
            Row {
                anchors.fill: parent
                anchors.margins: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Constants.iconSizeMedium + Constants.spacingSmall
                    height: Constants.iconSizeMedium + Constants.spacingSmall
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface2
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
                    Text {
                        anchors.centerIn: parent
                        text: conversation ? conversation.contactName.charAt(0).toUpperCase() : ""
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: Font.Bold
                        color: MColors.accent
                    }
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: conversation ? conversation.contactName : ""
                    font.pixelSize: Constants.fontSizeLarge
                    font.weight: Font.Bold
                    color: MColors.text
                }
            }
        }
        
        ListView {
            id: messagesList
            width: parent.width
            height: parent.height - parent.children[0].height - parent.children[2].height
            clip: true
            topMargin: Constants.spacingMedium
            verticalLayoutDirection: ListView.BottomToTop
            spacing: Constants.spacingSmall
            
            model: messages.slice().reverse()
            
            delegate: Item {
                width: messagesList.width
                height: messageBubble.height + timestampText.height + Constants.spacingSmall * 2
                
                Column {
                    anchors.left: modelData.isOutgoing ? undefined : parent.left
                    anchors.right: modelData.isOutgoing ? parent.right : undefined
                    anchors.margins: Constants.spacingMedium
                    spacing: Constants.spacingXSmall
                    
                    Rectangle {
                        id: messageBubble
                        width: Math.min(messageText.implicitWidth + Constants.spacingMedium * 2, messagesList.width * 0.75)
                        height: messageText.implicitHeight + Constants.spacingMedium * 2
                        radius: Constants.borderRadiusSharp
                        color: modelData.isOutgoing ? MColors.accent : MColors.surface
                        border.width: Constants.borderWidthThin
                        border.color: modelData.isOutgoing ? MColors.accentDark : MColors.border
                        antialiasing: Constants.enableAntialiasing
                        
                        Text {
                            id: messageText
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            text: modelData.text
                            font.pixelSize: Constants.fontSizeMedium
                            color: modelData.isOutgoing ? MColors.text : MColors.text
                            wrapMode: Text.Wrap
                        }
                    }
                    
                    Text {
                        id: timestampText
                        text: new Date(modelData.timestamp).toLocaleTimeString(Qt.locale(), "h:mm AP")
                        font.pixelSize: Constants.fontSizeXSmall
                        color: MColors.textTertiary
                        anchors.left: modelData.isOutgoing ? undefined : parent.left
                        anchors.right: modelData.isOutgoing ? parent.right : undefined
                    }
                }
            }
        }
        
        Rectangle {
            width: parent.width
            height: Constants.touchTargetLarge
            color: MColors.surface
            
            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }
            
            Row {
                anchors.fill: parent
                anchors.margins: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                MTextInput {
                    id: messageInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.spacing - Constants.touchTargetMedium
                    placeholderText: "Type a message..."
                }
                
                MIconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "send"
                    size: Constants.touchTargetMedium
                    variant: messageInput.text.length > 0 ? "primary" : "secondary"
                    enabled: messageInput.text.length > 0
                    onClicked: {
                        if (messageInput.text.length > 0 && conversation) {
                            Logger.info("Messages", "Sending message to: " + conversation.contactName)
                            var recipientNumber = conversation.contactNumber || conversation.id.replace("conv_", "")
                            if (typeof SMSService !== 'undefined') {
                                SMSService.sendMessage(recipientNumber, messageInput.text)
                            }
                            messageInput.text = ""
                        }
                    }
                }
            }
        }
    }
}

