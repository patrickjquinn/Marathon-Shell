pragma Singleton
import QtQml.Models
ListModel {
    property var read: []
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
}
