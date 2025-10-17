import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    color: MColors.background
    
    property var conversation
    property var messages: [
        { id: 1, text: "Hey! How are you?", sent: false, timestamp: Date.now() - 1000 * 60 * 60 },
        { id: 2, text: "I'm good! How about you?", sent: true, timestamp: Date.now() - 1000 * 60 * 50 },
        { id: 3, text: "Great! Want to grab lunch tomorrow?", sent: false, timestamp: Date.now() - 1000 * 60 * 40 },
        { id: 4, text: "Sure! What time works for you?", sent: true, timestamp: Date.now() - 1000 * 60 * 30 },
        { id: 5, text: "How about 12:30?", sent: false, timestamp: Date.now() - 1000 * 60 * 20 },
        { id: 6, text: "See you tomorrow!", sent: false, timestamp: Date.now() - 1000 * 60 * 15 }
    ]
    
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
            verticalLayoutDirection: ListView.BottomToTop
            spacing: Constants.spacingSmall
            
            model: messages.slice().reverse()
            
            delegate: Item {
                width: messagesList.width
                height: messageBubble.height + Constants.spacingSmall
                
                Rectangle {
                    id: messageBubble
                    anchors.left: modelData.sent ? undefined : parent.left
                    anchors.right: modelData.sent ? parent.right : undefined
                    anchors.margins: Constants.spacingMedium
                    width: Math.min(messageText.implicitWidth + Constants.spacingMedium * 2, parent.width * 0.75)
                    height: messageText.implicitHeight + Constants.spacingMedium * 2
                    radius: Constants.borderRadiusSharp
                    color: modelData.sent ? MColors.accent : MColors.surface
                    border.width: Constants.borderWidthThin
                    border.color: modelData.sent ? MColors.accentDark : MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
                    Text {
                        id: messageText
                        anchors.fill: parent
                        anchors.margins: Constants.spacingMedium
                        text: modelData.text
                        font.pixelSize: Constants.fontSizeMedium
                        color: modelData.sent ? MColors.text : MColors.text
                        wrapMode: Text.Wrap
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
                        if (messageInput.text.length > 0) {
                            console.log("Send message:", messageInput.text)
                            messages.push({
                                id: messages.length + 1,
                                text: messageInput.text,
                                sent: true,
                                timestamp: Date.now()
                            })
                            messageInput.text = ""
                        }
                    }
                }
            }
        }
    }
}

