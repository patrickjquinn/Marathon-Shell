pragma Singleton
import QtQml
// As the C++: every turnScreenOn re-asserts the panel; screenOn changes only on an edge.
QtObject {
    property bool screenOn: true
    function turnScreenOn() { screenOn = true; DisplayManagerCpp.screenStateChanged(true); }
    function turnScreenOff(reason) { screenOn = false; DisplayManagerCpp.screenStateChanged(false); }
    function forceScreenOn() { screenOn = true; DisplayManagerCpp.screenStateChanged(true); screenOnChanged(); }
}
