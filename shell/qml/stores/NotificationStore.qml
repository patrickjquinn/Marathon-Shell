pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: notificationStore
    
    property var notifications: NotificationModel
    property int unreadCount: NotificationModel ? NotificationModel.unreadCount : 0
    
    signal notificationAdded(var notification)
    signal notificationRemoved(string id)
    signal notificationRead(string id)
    
    function addNotification(notification) {
        if (typeof NotificationModel !== 'undefined') {
            var id = NotificationModel.addNotification(
                notification.appId || "system",
                notification.title || "",
                notification.body || notification.content || notification.subtitle || "",
                notification.icon || ""
            )
            notificationAdded(notification)
            Logger.info("NotificationStore", "Added: " + notification.title)
            return id
        }
        return -1
    }
    
    function removeNotification(id) {
        if (typeof NotificationModel !== 'undefined') {
            NotificationModel.dismissNotification(parseInt(id) || id)
            notificationRemoved(id)
            Logger.info("NotificationStore", "Removed: " + id)
        }
    }
    
    function markAsRead(id) {
        if (typeof NotificationModel !== 'undefined') {
            NotificationModel.markAsRead(parseInt(id) || id)
            notificationRead(id)
            Logger.debug("NotificationStore", "Marked as read: " + id)
        }
    }
    
    function clearAll() {
        if (typeof NotificationModel !== 'undefined') {
            NotificationModel.dismissAllNotifications()
            Logger.info("NotificationStore", "All cleared")
        }
    }
    
    Component.onCompleted: {
        console.log("[NotificationStore] Initialized with C++ NotificationModel")
        if (typeof NotificationModel !== 'undefined') {
            console.log("[NotificationStore] Initial notification count:", NotificationModel.count)
        }
    }
}
