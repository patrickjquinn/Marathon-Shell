import QtQuick
import QtQuick.Window

Window {
    id: window
    width: 720
    height: 720
    visible: true
    title: "Marathon OS - Bandit"
    color: "#000000"
    
    MarathonShell {
        anchors.fill: parent
        focus: true
    }
}

