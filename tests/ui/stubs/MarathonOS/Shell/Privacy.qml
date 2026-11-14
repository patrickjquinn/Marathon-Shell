pragma Singleton
import QtQml

QtObject {
    property bool camera: false
    property bool microphone: false
    property var cameraUsers: []
    property var microphoneUsers: []
}
