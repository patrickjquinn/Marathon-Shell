pragma Singleton
import QtQml.Models
ListModel {
    property var read: []
    property var clicked: []
    property var notifications: []
    property var dismissed: []
    property bool dismissedAll: false
    property var triggered: []
    signal notificationDismissed(int id)
    function markAsRead(id) { read = read.concat([id]); }
    function sources() {
        const out = [];
        for (let i = 0; i < count; i++) {
            const n = get(i);
            let s = out.find(o => o.appId === n.appId);
            if (!s) {
                s = { appId: n.appId, unread: 0 };
                out.push(s);
            }
            if (!n.isRead)
                s.unread++;
        }
        return out;
    }
    function getNotificationCountForApp(appId) {
        return notifications.filter(n => n.appId === appId && !n.read).length;
    }
    function clickNotification(id) { clicked = clicked.concat([id]); }
    function triggerAction(id, key) { triggered = triggered.concat([id + ":" + key]); }
    function dismissNotification(id) { dismissed = dismissed.concat([id]); }
    function dismissAllNotifications() { dismissedAll = true; }
}
