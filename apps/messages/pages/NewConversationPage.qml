import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: newConversationPage
    color: MColors.background
    
    signal conversationStarted(string recipient, string recipientName)
    signal cancelled()
    
    property string selectedContact: ""
    property string selectedContactName: ""
    
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
                
                MIconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "x"
                    iconSize: Constants.touchTargetMedium
                    onClicked: {
                        cancelled()
                    }
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "New Message"
                    font.pixelSize: Constants.fontSizeLarge
                    font.weight: Font.Bold
                    color: MColors.textPrimary
                }
            }
        }
        
        Column {
            width: parent.width
            height: parent.height - parent.children[0].height
            spacing: 0
            
            Rectangle {
                width: parent.width
                height: Constants.touchTargetLarge
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
                    
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "To:"
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }
                    
                    MTextInput {
                        id: recipientInput
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.children[0].width - parent.children[2].width - parent.spacing * 2
                        placeholderText: "Phone number or contact name"
                        text: selectedContactName || selectedContact
                        enabled: selectedContact.length === 0
                        
                        onTextChanged: {
                            if (selectedContact.length === 0) {
                                searchTimer.restart()
                            }
                        }
                    }
                    
                    MIconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "chevron-right"
                        iconSize: Constants.touchTargetMedium
                        enabled: selectedContact.length > 0 || recipientInput.text.length > 0
                        onClicked: {
                            startConversation()
                        }
                    }
                }
            }
            
            Timer {
                id: searchTimer
                interval: 300
                repeat: false
                onTriggered: {
                    if (recipientInput.text.length > 0 && typeof ContactsManager !== 'undefined') {
                        contactsList.model = ContactsManager.searchContacts(recipientInput.text)
                    }
                }
            }
            
            ListView {
                id: contactsList
                width: parent.width
                height: parent.height - parent.children[0].height
                clip: true
                
                model: typeof ContactsManager !== 'undefined' ? ContactsManager.contacts : []
                
                delegate: Rectangle {
                    width: contactsList.width
                    height: Constants.touchTargetLarge
                    color: "transparent"
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingXSmall
                        color: MColors.surface
                        radius: Constants.borderRadiusSharp
                        border.width: Constants.borderWidthThin
                        border.color: MColors.border
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            spacing: Constants.spacingMedium
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.iconSizeMedium + Constants.spacingSmall
                                height: Constants.iconSizeMedium + Constants.spacingSmall
                                radius: Constants.borderRadiusSharp
                                color: MColors.elevated
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                                    font.pixelSize: Constants.fontSizeMedium
                                    font.weight: Font.Bold
                                    color: MColors.marathonTeal
                                }
                            }
                            
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - parent.children[0].width - parent.spacing
                                spacing: Constants.spacingXSmall
                                
                                Text {
                                    width: parent.width
                                    text: modelData.name
                                    font.pixelSize: Constants.fontSizeMedium
                                    font.weight: Font.DemiBold
                                    color: MColors.textPrimary
                                    elide: Text.ElideRight
                                }
                                
                                Text {
                                    text: modelData.phone
                                    font.pixelSize: Constants.fontSizeSmall
                                    color: MColors.textSecondary
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                parent.color = MColors.elevated
                                HapticService.light()
                            }
                            onReleased: {
                                parent.color = MColors.surface
                            }
                            onCanceled: {
                                parent.color = MColors.surface
                            }
                            onClicked: {
                                selectedContact = modelData.phone
                                selectedContactName = modelData.name
                                recipientInput.text = modelData.name
                                Logger.info("NewConversation", "Selected contact: " + modelData.name)
                            }
                        }
                    }
                }
            }
        }
    }
    
    function startConversation() {
        var recipient = selectedContact.length > 0 ? selectedContact : recipientInput.text
        var name = selectedContactName.length > 0 ? selectedContactName : recipient
        
        if (recipient.length > 0) {
            Logger.info("NewConversation", "Starting conversation with: " + recipient)
            conversationStarted(recipient, name)
        }
    }
}

