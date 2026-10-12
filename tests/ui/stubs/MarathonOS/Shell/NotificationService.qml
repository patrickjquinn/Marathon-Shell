pragma Singleton
import QtQml
QtObject {
    property var clicked: []
    function clickNotification(id) { clicked = clicked.concat([id]); }
}
