import MarathonOS.Shell
import QtQuick
import QtQuick.Window

// marathon-shell-bin --home-unlock: the boot PIN pad for the encrypted /home.
Window {
    visibility: Window.FullScreen
    title: "Marathon OS - Unlock"  // i18n: not user-facing
    color: "#000000"

    MarathonHomeUnlock {
        anchors.fill: parent
        unlock: HomeUnlockCpp
    }
}
