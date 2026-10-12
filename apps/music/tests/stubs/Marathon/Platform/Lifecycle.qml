pragma Singleton
import QtQml

QtObject {
    property int held: 0

    function beginBackgroundTask(category, reason) {
        held++;
        return 7;
    }

    function endBackgroundTask(handle) {
        if (handle === 7)
            held--;
        return true;
    }
}
