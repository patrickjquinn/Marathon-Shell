import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import "./pages"

MApp {
    id: messagesApp
    appId: "messages"
    appName: "Messages"
    appIcon: "assets/icon.svg"
    
    property var conversations: [
        {
            id: 1,
            contactName: "Alice Johnson",
            lastMessage: "See you tomorrow!",
            timestamp: Date.now() - 1000 * 60 * 15,
            unread: 2
        },
        {
            id: 2,
            contactName: "Bob Smith",
            lastMessage: "Thanks for the help",
            timestamp: Date.now() - 1000 * 60 * 60 * 2,
            unread: 0
        },
        {
            id: 3,
            contactName: "Carol Williams",
            lastMessage: "Can you call me?",
            timestamp: Date.now() - 1000 * 60 * 60 * 4,
            unread: 1
        },
        {
            id: 4,
            contactName: "David Brown",
            lastMessage: "Got it, will do 👍",
            timestamp: Date.now() - 1000 * 60 * 60 * 24,
            unread: 0
        },
        {
            id: 5,
            contactName: "Emma Davis",
            lastMessage: "Perfect! See you there",
            timestamp: Date.now() - 1000 * 60 * 60 * 24 * 2,
            unread: 0
        }
    ]
    
    property int selectedConversationId: -1
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        StackView {
            id: navigationStack
            anchors.fill: parent
            initialItem: conversationsListPage
            
            property var backConnection: null
            
            onDepthChanged: {
                messagesApp.navigationDepth = depth - 1
            }
            
            Component.onCompleted: {
                messagesApp.navigationDepth = depth - 1
                
                backConnection = messagesApp.backPressed.connect(function() {
                    if (depth > 1) {
                        pop()
                    }
                })
            }
            
            Component.onDestruction: {
                if (backConnection) {
                    messagesApp.backPressed.disconnect(backConnection)
                }
            }
            
            pushEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: navigationStack.width
                    to: 0
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
            }
            
            pushExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -navigationStack.width * 0.3
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1.0
                    to: 0.0
                    duration: Constants.animationDurationNormal
                }
            }
            
            popEnter: Transition {
                NumberAnimation {
                    property: "x"
                    from: -navigationStack.width * 0.3
                    to: 0
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0.0
                    to: 1.0
                    duration: Constants.animationDurationNormal
                }
            }
            
            popExit: Transition {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: navigationStack.width
                    duration: Constants.animationDurationNormal
                    easing.type: Easing.OutCubic
                }
            }
        }
        
        Component {
            id: conversationsListPage
            ConversationsListPage {
                onOpenConversation: function(conversationId) {
                    selectedConversationId = conversationId
                    var conversation = getConversation(conversationId)
                    if (conversation) {
                        navigationStack.push(chatPage, { conversation: conversation })
                    }
                }
            }
        }
        
        Component {
            id: chatPage
            ChatPage {}
        }
    }
    
    function getConversation(id) {
        for (var i = 0; i < conversations.length; i++) {
            if (conversations[i].id === id) {
                return conversations[i]
            }
        }
        return null
    }
    
    function formatTimestamp(timestamp) {
        var now = Date.now()
        var diff = now - timestamp
        
        if (diff < 1000 * 60 * 60) {
            return Math.floor(diff / (1000 * 60)) + "m"
        } else if (diff < 1000 * 60 * 60 * 24) {
            return Math.floor(diff / (1000 * 60 * 60)) + "h"
        } else {
            return Math.floor(diff / (1000 * 60 * 60 * 24)) + "d"
        }
    }
}
