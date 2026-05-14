import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Lock screen bottom chrome.
//
// Distinct from MDock — lock screens use a simpler row: phone icon
// teal lower-left, camera icon dim lower-right, HomeIndicator at the
// base. No layers/page-indicator, no inbox, no dots. This matches
// the LockScreen / LockMedia / LockNowBar variants in the handoff.
//
// Caller positions this with anchors.bottom + anchors.left/right.
Item {
    id: root

    signal phoneActivated
    signal cameraActivated

    implicitHeight: 64

    // Phone shortcut — bottom-left, teal.
    Icon {
        id: phoneIcon
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 24
        anchors.bottomMargin: 16
        name: "phone"
        size: 26
        color: MColors.marathonTealBright

        MouseArea {
            anchors.fill: parent
            anchors.margins: -12 // generous hit area, per A11y rule
            onClicked: root.phoneActivated()
        }
    }

    // Camera shortcut — bottom-right, dim primary.
    Icon {
        id: cameraIcon
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 24
        anchors.bottomMargin: 16
        name: "camera"
        size: 24
        // Dim primary, not secondary — design renders this clearly
        // visible but lower-weight than the active phone icon.
        color: Qt.rgba(1, 1, 1, 0.85)

        MouseArea {
            anchors.fill: parent
            anchors.margins: -12
            onClicked: root.cameraActivated()
        }
    }
}
