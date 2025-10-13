pragma Singleton
import QtQuick

QtObject {
    id: notificationService
    
    property var notifications: []
    property int unreadCount: 0
    property int notificationIdCounter: 1000
    
    property bool notificationsEnabled: true
    property bool soundEnabled: true
    property bool vibrationEnabled: true
    property bool ledEnabled: true
    property bool isDndEnabled: false
    
    signal notificationReceived(var notification)
    signal notificationDismissed(int id)
    signal notificationClicked(int id)
    signal notificationActionTriggered(int id, string action)
    
    function sendNotification(appId, title, body, options) {
        if (!notificationsEnabled) {
            console.log("[NotificationService] Notifications disabled, ignoring")
            return -1
        }
        
        var id = notificationIdCounter++
        var timestamp = new Date().toISOString()
        
        var notification = {
            id: id,
            appId: appId || "system",
            title: title || "",
            body: body || "",
            icon: options?.icon || "",
            image: options?.image || "",
            category: options?.category || "message",
            priority: options?.priority || "normal",
            actions: options?.actions || [],
            persistent: options?.persistent || false,
            timestamp: timestamp,
            read: false
        }
        
        notifications.push(notification)
        unreadCount++
        
        console.log("[NotificationService] Notification sent:", id, title)
        notificationReceived(notification)
        
        if (soundEnabled && !AudioManager.dndEnabled) {
            AudioManager.playSound("notification")
        }
        
        if (vibrationEnabled && !AudioManager.dndEnabled) {
            AudioManager.vibrate([50, 100, 50])
        }
        
        _platformNotify(notification)
        
        return id
    }
    
    function dismissNotification(id) {
        console.log("[NotificationService] Dismissing notification:", id)
        
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id) {
                if (!notifications[i].read) {
                    unreadCount = Math.max(0, unreadCount - 1)
                }
                notifications.splice(i, 1)
                notificationDismissed(id)
                _platformDismissNotification(id)
                break
            }
        }
    }
    
    function dismissAllNotifications() {
        console.log("[NotificationService] Dismissing all notifications")
        notifications = []
        unreadCount = 0
        _platformDismissAllNotifications()
    }
    
    function markAsRead(id) {
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id && !notifications[i].read) {
                notifications[i].read = true
                unreadCount = Math.max(0, unreadCount - 1)
                break
            }
        }
    }
    
    function markAllAsRead() {
        console.log("[NotificationService] Marking all as read")
        for (var i = 0; i < notifications.length; i++) {
            notifications[i].read = true
        }
        unreadCount = 0
    }
    
    function clickNotification(id) {
        console.log("[NotificationService] Notification clicked:", id)
        markAsRead(id)
        notificationClicked(id)
        _platformNotificationClicked(id)
    }
    
    function triggerAction(id, action) {
        console.log("[NotificationService] Action triggered:", id, action)
        notificationActionTriggered(id, action)
        _platformNotificationAction(id, action)
    }
    
    function getNotification(id) {
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id) {
                return notifications[i]
            }
        }
        return null
    }
    
    function getNotificationsByApp(appId) {
        return notifications.filter(function(n) {
            return n.appId === appId
        })
    }
    
    function getUnreadNotifications() {
        return notifications.filter(function(n) {
            return !n.read
        })
    }
    
    function getNotificationCountForApp(appId) {
        var count = 0
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].appId === appId && !notifications[i].read) {
                count++
            }
        }
        return count
    }
    
    function _platformNotify(notification) {
        if (Platform.isLinux) {
            console.log("[NotificationService] Sending D-Bus notification to org.freedesktop.Notifications")
        } else if (Platform.isMacOS) {
            console.log("[NotificationService] macOS NSUserNotification")
        }
    }
    
    function _platformDismissNotification(id) {
        if (Platform.isLinux) {
            console.log("[NotificationService] D-Bus CloseNotification:", id)
        }
    }
    
    function _platformDismissAllNotifications() {
        if (Platform.isLinux) {
            console.log("[NotificationService] Dismissing all via D-Bus")
        }
    }
    
    function _platformNotificationClicked(id) {
        if (Platform.isLinux) {
            console.log("[NotificationService] D-Bus NotificationClosed with reason 2 (clicked)")
        }
    }
    
    function _platformNotificationAction(id, action) {
        if (Platform.isLinux) {
            console.log("[NotificationService] D-Bus ActionInvoked:", id, action)
        }
    }
    
    function _populateTestNotifications() {
        sendNotification("messages", "John Doe", "Hey, are you free tonight?", {
            icon: "qrc:/images/messages.svg",
            category: "message",
            priority: "high",
            actions: ["reply", "dismiss"]
        })
        
        sendNotification("email", "Work Email", "Meeting moved to 3pm", {
            icon: "qrc:/images/calendar.svg",
            category: "email",
            priority: "normal"
        })
        
        sendNotification("system", "System Update", "Software update available", {
            icon: "qrc:/images/settings.svg",
            category: "system",
            priority: "low"
        })
    }
    
    Component.onCompleted: {
        console.log("[NotificationService] Initialized")
        
        if (!Platform.isLinux && !Platform.isMacOS) {
            _populateTestNotifications()
        }
    }
}

