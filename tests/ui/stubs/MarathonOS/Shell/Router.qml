pragma Singleton
import QtQml
QtObject {
    property int hubOpened: 0
    function goToHub() { hubOpened++; }
}
