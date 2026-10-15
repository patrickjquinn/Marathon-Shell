pragma Singleton
import QtQml

QtObject {
    property bool available: true

    function reset() {
        available = true;
    }
}
