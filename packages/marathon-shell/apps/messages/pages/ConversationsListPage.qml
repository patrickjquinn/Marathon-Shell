import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Page {
    id: conversationsPage
    
    signal openConversation(int conversationId)
    
    background: Rectangle {
        color: MColors.background
    }
    
    Flickable {
        id: scrollView
        anchors.fill: parent
        contentHeight: messagesContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: 1500
        maximumFlickVelocity: 2500
        
        Column {
            id: messagesContent
            width: parent.width
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24
            
            // Page title
            Text {
                text: "Messages"
                color: MColors.text
                font.pixelSize: Constants.fontSizeXLarge
                font.weight: Font.Bold
                font.family: MTypography.fontFamily
            }
            
            // Recent Conversations
            Section {
                title: "Recent Conversations"
                subtitle: "Your message conversations"
                width: parent.width - 48
                
                Repeater {
                    model: messagesApp.conversations
                    
                    SettingsListItem {
                        title: modelData.contactName
                        subtitle: modelData.lastMessage
                        iconName: "message-circle"
                        showChevron: true
                        value: messagesApp.formatTimestamp(modelData.timestamp)
                        onSettingClicked: {
                            openConversation(modelData.id)
                        }
                    }
                }
            }
            
            Item { height: 40 }
        }
    }
}

