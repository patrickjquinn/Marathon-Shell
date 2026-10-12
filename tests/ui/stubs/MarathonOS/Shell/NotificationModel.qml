pragma Singleton
import QtQml.Models
ListModel {
    property var read: []
    function markAsRead(id) { read = read.concat([id]); }
}
