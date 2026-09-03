import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Lock screen bottom chrome — JSX LockScreen (screens-shell.jsx:51) renders
// the phone and camera as bare ~24 px outline glyphs in the bottom corners,
// not in any bay container. Tap targets are oversized via MouseArea margins
// so the affordance stays reachable without a visible chip behind it.
Item {
    id: root

    signal phoneActivated
    signal cameraActivated

    implicitHeight: Math.round(48 * Constants.scaleFactor)

    readonly property int glyphSize: Math.round(24 * Constants.scaleFactor)
    readonly property int sideInset: Math.round(28 * Constants.scaleFactor)

    Item {
        id: phoneHit
        width: Math.round(48 * Constants.scaleFactor)
        height: Math.round(48 * Constants.scaleFactor)
        anchors.left: parent.left
        anchors.leftMargin: root.sideInset - width / 2 + root.glyphSize / 2
        anchors.verticalCenter: parent.verticalCenter

        Icon {
            id: phoneIcon
            anchors.centerIn: parent
            name: "phone"
            size: root.glyphSize
            color: MColors.textPrimary
            opacity: phoneArea.pressed ? 0.55 : 1.0
            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.micro
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: phoneArea
            anchors.fill: parent
            onClicked: root.phoneActivated()
        }
    }

    Item {
        id: cameraHit
        width: Math.round(48 * Constants.scaleFactor)
        height: Math.round(48 * Constants.scaleFactor)
        anchors.right: parent.right
        anchors.rightMargin: root.sideInset - width / 2 + root.glyphSize / 2
        anchors.verticalCenter: parent.verticalCenter

        Icon {
            id: cameraIcon
            anchors.centerIn: parent
            name: "camera"
            size: root.glyphSize
            color: MColors.textPrimary
            opacity: cameraArea.pressed ? 0.55 : 1.0
            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.micro
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: cameraArea
            anchors.fill: parent
            onClicked: root.cameraActivated()
        }
    }
}
