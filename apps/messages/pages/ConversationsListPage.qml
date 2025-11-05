import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Page {
    id: conversationsPage
    
    signal openConversation(int conversationId)
    signal newMessage()
    
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
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24
            
            // Page title
            Text {
                text: "Messages"
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeXLarge
                font.weight: Font.Bold
                font.family: MTypography.fontFamily
            }
            
            // Recent Conversations
            MSection {
                title: "Recent Conversations"
                subtitle: "Your message conversations"
                width: parent.width - 48
                
                Column {
                    width: parent.width
                    spacing: MSpacing.sm
                    
                    Repeater {
                        model: messagesApp.conversations
                        
                        Rectangle {
                            width: parent.width
                            height: Constants.touchTargetLarge + MSpacing.md
                            color: "transparent"
                            
                            Rectangle {
                                id: deleteButton
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: MSpacing.sm
                                width: Constants.touchTargetLarge
                                color: "#E74C3C"
                                radius: Constants.borderRadiusSharp
                                visible: conversationItem.x < -20
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "trash"
                                    size: Constants.iconSizeMedium
                                    color: "white"
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        if (typeof SMSService !== 'undefined') {
                                            SMSService.deleteConversation(modelData.id)
                                        }
                                    }
                                }
                            }
                            
                            Rectangle {
                                id: conversationItem
                                anchors.fill: parent
                                anchors.margins: MSpacing.sm
                                color: MColors.surface
                                radius: Constants.borderRadiusSharp
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border
                                
                                Behavior on x {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                                }
                                
                                MSettingsListItem {
                                    anchors.fill: parent
                                    title: modelData.contactName
                                    subtitle: modelData.lastMessage
                                    iconName: "message-circle"
                                    showChevron: true
                                    value: messagesApp.formatTimestamp(modelData.timestamp)
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    property real startX: 0
                                    
                                    onPressed: {
                                        startX = mouse.x
                                        HapticService.light()
                                    }
                                    onReleased: {
                                        if (conversationItem.x < -100) {
                                            if (typeof SMSService !== 'undefined') {
                                                SMSService.deleteConversation(modelData.id)
                                            }
                                        } else {
                                            conversationItem.x = 0
                                        }
                                    }
                                    onCanceled: {
                                        conversationItem.x = 0
                                    }
                                    onPositionChanged: {
                                        if (pressed) {
                                            var delta = mouse.x - startX
                                            if (delta < 0) {
                                                conversationItem.x = Math.max(delta, -120)
                                            }
                                        }
                                    }
                                    onClicked: {
                                        if (conversationItem.x === 0) {
                                            openConversation(modelData.id)
                                        } else {
                                            conversationItem.x = 0
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            Item { height: 40 }
        }
    }
    
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.lg
        width: Constants.touchTargetLarge
        height: Constants.touchTargetLarge
        radius: Constants.touchTargetLarge / 2
        color: MColors.marathonTeal
        border.width: Constants.borderWidthThick
        border.color: MColors.marathonTealDark
        antialiasing: true
        
        Icon {
            anchors.centerIn: parent
            name: "plus"
            size: Constants.iconSizeLarge
            color: MColors.textPrimary
        }
        
        MouseArea {
            anchors.fill: parent
            onPressed: {
                parent.scale = 0.9
                HapticService.medium()
            }
            onReleased: {
                parent.scale = 1.0
            }
            onCanceled: {
                parent.scale = 1.0
            }
            onClicked: {
                Logger.info("Messages", "New message")
                newMessage()
            }
        }
        
        Behavior on scale {
            NumberAnimation { duration: 100 }
        }
    }
}

