import QtQuick
import QtQuick.Window

Window {
    id: window

    width: 540
    height: 1140
    visible: true
    title: "Marathon OS - Bandit"
    color: "#000000"

    MarathonShell {
        anchors.fill: parent
        focus: true
    }
}
