pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: notificationStore
    
    property var notifications: NotificationService.notifications
    
    property int unreadCount: NotificationService.unreadCount
    
    signal notificationAdded(var notification)
    signal notificationRemoved(string id)
    signal notificationRead(string id)
    
    function addNotification(notification) {
        var id = NotificationService.sendNotification(
            notification.appId || "system",
            notification.title || "",
            notification.body || notification.content || notification.subtitle || "",
            {
                icon: notification.icon || "",
                category: notification.type || "message",
                priority: "normal"
            }
        )
        notificationAdded(notification)
        Logger.info("NotificationStore", "Added: " + notification.title)
        return id
    }
    
    function removeNotification(id) {
        NotificationService.dismissNotification(parseInt(id) || id)
        notificationRemoved(id)
        Logger.info("NotificationStore", "Removed: " + id)
    }
    
    function markAsRead(id) {
        NotificationService.markAsRead(parseInt(id) || id)
        notificationsChanged()
        notificationRead(id)
        Logger.debug("NotificationStore", "Marked as read: " + id)
    }
    
    function clearAll() {
        NotificationService.dismissAllNotifications()
        Logger.info("NotificationStore", "All cleared")
    }
    
    property Connections notificationServiceConnections: Connections {
        target: NotificationService
        function onNotificationReceived(notification) {
            notificationsChanged()
            notificationAdded(notification)
        }
        function onNotificationDismissed(id) {
            notificationsChanged()
            notificationRemoved(id)
        }
    }
    
    Component.onCompleted: {
        console.log("[NotificationStore] Initialized with real NotificationService")
        console.log("[NotificationStore] Initial notification count:", notifications.length)
    }
}
