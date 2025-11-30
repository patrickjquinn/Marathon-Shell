pragma Singleton
import QtQuick

QtObject {
    id: serviceBus

    signal powerManagerChanged
    signal networkManagerChanged
    signal displayManagerChanged
    signal audioManagerChanged
    signal notificationServiceChanged
    signal telephonyManagerChanged
    signal locationServiceChanged
    signal bluetoothManagerChanged

    signal systemResumed
    signal systemSuspending
    signal systemShuttingDown

    function emit(signalName, data) {
        console.log("[ServiceBus] Emitting:", signalName, JSON.stringify(data));
    }
}
