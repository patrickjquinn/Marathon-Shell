import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Lock screen bottom chrome.
//
// JSX LockScreen (screens-shell.jsx:51) shows only a chevron + 'Swipe
// up to unlock' at the bottom, but the project keeps phone+camera
// shortcuts there for usability (per-product decision — emergency
// access from lock is a near-universal mobile pattern). The two
// shortcuts use the same squircle-bay treatment as the home dock:
// 56 × 56 squircle, teal gradient + black glyph for the primary
// (Phone), bb10-card gradient + teal glyph for the secondary
// (Camera). Caller anchors the row to bottom.
Item {
    id: root

    signal phoneActivated
    signal cameraActivated

    implicitHeight: Math.round(72 * Constants.scaleFactor)

    readonly property int bayWidth: Math.round(56 * Constants.scaleFactor)

    Rectangle {
        id: phoneBay
        width: root.bayWidth
        height: root.bayWidth
        radius: MRadius.squircle
        anchors.left: parent.left
        anchors.leftMargin: Math.round(20 * Constants.scaleFactor)
        anchors.verticalCenter: parent.verticalCenter
        border.width: 1
        border.color: MColors.tealBorder

        gradient: Gradient {
            GradientStop {
                position: 0
                color: MColors.marathonTealBright
            }
            GradientStop {
                position: 1
                color: MColors.marathonTealDark
            }
        }

        Icon {
            anchors.centerIn: parent
            name: "phone"
            size: 26
            color: "#000000"
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: root.phoneActivated()
            onPressed: phoneBay.scale = 0.94
            onReleased: phoneBay.scale = 1.0
            onCanceled: phoneBay.scale = 1.0
        }

        Behavior on scale {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutBack
            }
        }
    }

    Rectangle {
        id: cameraBay
        width: root.bayWidth
        height: root.bayWidth
        radius: MRadius.squircle
        anchors.right: parent.right
        anchors.rightMargin: Math.round(20 * Constants.scaleFactor)
        anchors.verticalCenter: parent.verticalCenter
        border.width: 1
        border.color: MColors.whiteOverlay08

        gradient: Gradient {
            GradientStop {
                position: 0
                color: MColors.bb10Card
            }
            GradientStop {
                position: 1
                color: MColors.bb10Black
            }
        }

        Icon {
            anchors.centerIn: parent
            name: "camera"
            size: 24
            color: MColors.marathonTealBright
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            onClicked: root.cameraActivated()
            onPressed: cameraBay.scale = 0.94
            onReleased: cameraBay.scale = 1.0
            onCanceled: cameraBay.scale = 1.0
        }

        Behavior on scale {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutBack
            }
        }
    }
}
