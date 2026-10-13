pragma Singleton
import QtQml
QtObject {
    property var clicked: []
    property var notifications: []
    function getNotificationCountForApp(appId) {
        return notifications.filter(n => n.appId === appId && !n.read).length;
    }
    property var dismissed: []
    property bool dismissedAll: false
    function clickNotification(id) { clicked = clicked.concat([id]); }
    function dismissNotification(id) { dismissed = dismissed.concat([id]); }
    function dismissAllNotifications() { dismissedAll = true; }
}
