pragma Singleton
import QtQml
QtObject {
    property int cancelledConnects: 0
    function cancelPendingConnection() { cancelledConnects++; }
}
