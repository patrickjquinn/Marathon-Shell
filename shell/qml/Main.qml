import QtQuick
import QtQuick.Window

Window {
    id: window
    // OnePlus 6 aspect ratio (9:19) scaled to 50% for desktop debugging
    // Actual device: 1080×2280, Debug window: 540×1140
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
