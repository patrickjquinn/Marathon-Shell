pragma Singleton
import QtQuick

QtObject {
    id: notificationStore
    
    property var notifications: [
        {
            id: "notif1",
            type: "email",
            title: "Welcome to BlackBerry Protect!",
            subtitle: "If your BlackBerry device is lost or stolen, you can sign in to...",
            content: "If your BlackBerry device is lost or stolen, you can sign in to...",
            time: "9:36 PM",
            date: "Tuesday, September 2, 2014",
            icon: "qrc:/images/messages.svg",
            read: false
        },
        {
            id: "notif2",
            type: "system",
            title: "Meeting Mode is Available",
            subtitle: "Would you like BlackBerry to automatically silence notifications during meetings?",
            content: "Would you like BlackBerry to automatically silence notifications during meetings?",
            time: "2:30 PM",
            date: "Friday, August 22, 2014",
            icon: "qrc:/images/bell.svg",
            read: false
        },
        {
            id: "notif3",
            type: "system",
            title: "New Time Zone",
            subtitle: "Pacific Time has been set.",
            content: "Pacific Time has been set.",
            time: "9:35 PM",
            date: "Tuesday, August 19, 2014",
            icon: "qrc:/images/clock.svg",
            read: false
        },
        {
            id: "notif4",
            type: "email",
            title: "BlackBerry",
            subtitle: "Welcome!",
            content: "Welcome!",
            time: "10:44 AM",
            date: "Tuesday, August 19, 2014",
            icon: "qrc:/images/messages.svg",
            read: true
        },
        {
            id: "notif5",
            type: "email",
            title: "BlackBerry",
            subtitle: "Introducing the BlackBerry Priority Hub",
            content: "Introducing the BlackBerry Priority Hub",
            time: "10:44 AM",
            date: "Tuesday, August 19, 2014",
            icon: "qrc:/images/messages.svg",
            read: true
        }
    ]
    
    property int unreadCount: {
        var count = 0
        for (var i = 0; i < notifications.length; i++) {
            if (!notifications[i].read) count++
        }
        return count
    }
    
    signal notificationAdded(var notification)
    signal notificationRemoved(string id)
    signal notificationRead(string id)
    
    function addNotification(notification) {
        notifications.unshift(notification)
        notificationsChanged()
        notificationAdded(notification)
        console.log("Notification added:", notification.title)
    }
    
    function removeNotification(id) {
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id) {
                notifications.splice(i, 1)
                notificationsChanged()
                notificationRemoved(id)
                console.log("Notification removed:", id)
                break
            }
        }
    }
    
    function markAsRead(id) {
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id) {
                notifications[i].read = true
                notificationsChanged()
                notificationRead(id)
                console.log("Notification marked as read:", id)
                break
            }
        }
    }
    
    function clearAll() {
        notifications = []
        console.log("All notifications cleared")
    }
}

