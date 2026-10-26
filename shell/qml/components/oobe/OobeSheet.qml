import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// A panel risen from the bottom over a scrim; a tap on the scrim closes it.
Item {
    id: root

    property bool open: false
    property alias title: header.text
    default property alias content: column.data

    visible: open || slide.running

    MouseArea {
        anchors.fill: parent
        opacity: root.open ? 1 : 0
        onClicked: root.open = false

        Behavior on opacity {
            OpacityAnimator {
                duration: MMotion.durationFor("entrance")
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Silica.Theme.rgba(Silica.Theme.overlayBackgroundColor, Silica.Theme.opacityOverlay)
        }
    }

    MouseArea {
        width: parent.width
        height: Math.min(column.height, parent.height)
        y: root.open ? parent.height - height : parent.height

        Behavior on y {
            NumberAnimation {
                id: slide

                duration: MMotion.durationFor("entrance")
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Silica.Theme.overlayBackgroundColor, 1)
        }

        Silica.PanelBackground {
            anchors.fill: parent
        }

        Silica.SilicaFlickable {
            anchors.fill: parent
            contentHeight: column.height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: column

                width: parent.width
                bottomPadding: Silica.Theme.paddingLarge

                Silica.SectionHeader {
                    id: header
                }
            }
        }
    }
}
