pragma Singleton
import QtQml
QtObject {
    property string callState: "idle"
    function answer() { callState = "active"; }
    function hangup() { callState = "idle"; }
}
