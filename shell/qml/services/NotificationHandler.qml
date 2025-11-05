pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: root
    
    function findNotification(id) {
        for (var i = 0; i < NotificationService.notifications.length; i++) {
            if (NotificationService.notifications[i].id === id) {
                return NotificationService.notifications[i]
            }
        }
        return null
    }
    
    function handleNotificationClick(id) {
        Logger.info("NotificationHandler", "Notification clicked: " + id)
        
        var notification = root.findNotification(id)
        if (!notification) {
            Logger.warn("NotificationHandler", "Notification not found: " + id)
            return
        }
        
        var appId = notification.appId
        
        if (appId === "phone") {
            NavigationRouter.navigate(appId, "history", {})
        } else if (appId === "messages") {
            var notifId = notification.id
            if (typeof notifId === "string" && notifId.startsWith("sms_")) {
                var parts = notifId.split("_")
                if (parts.length >= 2) {
                    var phoneNumber = parts[1]
                    NavigationRouter.navigate(appId, "conversation", { number: phoneNumber })
                } else {
                    NavigationRouter.navigate(appId, "", {})
                }
            } else {
                NavigationRouter.navigate(appId, "", {})
            }
        } else {
            NavigationRouter.navigate(appId, "", {})
        }
        
        NotificationService.dismissNotification(id)
    }
    
    function handleNotificationAction(id, action) {
        Logger.info("NotificationHandler", "Notification action: " + action + " for ID: " + id)
        
        var notification = root.findNotification(id)
        if (!notification) {
            Logger.warn("NotificationHandler", "Notification not found: " + id)
            return
        }
        
        if (notification.appId === "phone") {
            if (action === "call_back") {
                var number = notification.body.replace("From: ", "")
                if (typeof TelephonyService !== 'undefined') {
                    TelephonyService.dial(number)
                }
                NavigationRouter.navigate("phone", "", {})
            } else if (action === "message") {
                var number2 = notification.body.replace("From: ", "")
                NavigationRouter.navigate("messages", "conversation", { number: number2 })
            }
        } else if (notification.appId === "messages") {
            if (action === "reply") {
                NavigationRouter.navigate("messages", "", {})
            } else if (action === "mark_read") {
                NotificationService.dismissNotification(id)
            }
        }
    }
}

