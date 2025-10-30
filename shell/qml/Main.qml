import QtQuick
import QtQuick.Window

Window {
    id: window
    width: 1080
    height: 2280
    visible: true
    title: "Marathon OS - Bandit"
    color: "#000000"
    
    MarathonShell {
        anchors.fill: parent
        focus: true
    }
}

