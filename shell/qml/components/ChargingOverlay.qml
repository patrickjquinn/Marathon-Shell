import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// A moment's battery at the centre of the screen when a charger comes or
// goes. Nothing is drawn between: the whole item is invisible at rest.
Item {
    id: overlay

    property bool plugged: false
    property int level: 0

    function show(pluggedIn, batteryLevel) {
        plugged = pluggedIn;
        level = Math.max(0, batteryLevel);
        play.restart();
    }

    enabled: false
    visible: platter.opacity > 0

    Rectangle {
        id: platter

        anchors.centerIn: parent
        width: Silica.Theme.itemSizeHuge * 1.6
        height: width
        radius: width / 2
        color: Silica.Theme.rgba("black", 0.72)
        opacity: 0
        scale: 0.9

        Column {
            anchors.centerIn: parent
            spacing: Silica.Theme.paddingMedium

            // The battery: a shell, its cap, and the charge filling it.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Silica.Theme.iconSizeLarge * 1.5
                height: Silica.Theme.iconSizeLarge * 0.75

                Rectangle {
                    id: shell

                    width: parent.width - cap.width
                    height: parent.height
                    radius: height * 0.2
                    color: "transparent"
                    border.width: Math.max(2, Math.round(height / 14))
                    border.color: Silica.Theme.primaryColor

                    Rectangle {
                        id: charge

                        property real fill: overlay.level / 100

                        x: shell.border.width * 2
                        y: x
                        height: parent.height - 2 * x
                        width: (parent.width - 2 * x) * fill
                        radius: Math.max(0, shell.radius - x)
                        color: overlay.plugged ? "#4cd964" : Silica.Theme.primaryColor
                    }
                    GlyphIcon {
                        anchors.centerIn: parent
                        visible: overlay.plugged
                        name: "lightning"
                        size: parent.height * 0.7
                        color: "black"
                    }
                }
                Rectangle {
                    id: cap

                    anchors.left: shell.right
                    anchors.verticalCenter: shell.verticalCenter
                    width: Math.max(3, Math.round(shell.height / 8))
                    height: shell.height * 0.4
                    radius: width / 2
                    color: Silica.Theme.primaryColor
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("%1%").arg(overlay.level)
                color: Silica.Theme.primaryColor
                font.family: Silica.Theme.fontFamilyHeading
                font.pixelSize: Silica.Theme.fontSizeLarge
                font.features: ({
                        "tnum": 1
                    })
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: overlay.plugged ? qsTr("Charging") : qsTr("Not charging")
                color: Silica.Theme.secondaryColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
            }
        }
    }

    SequentialAnimation {
        id: play

        ParallelAnimation {
            NumberAnimation {
                target: platter
                property: "opacity"
                from: 0
                to: 1
                duration: MMotion.reduceMotion ? 0 : 180
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: platter
                property: "scale"
                from: 0.9
                to: 1
                duration: MMotion.reduceMotion ? 0 : 260
                easing.type: Easing.OutBack
            }
            // Charge sweeps in on a charger, drains out without one.
            NumberAnimation {
                target: charge
                property: "fill"
                from: overlay.plugged ? 0 : overlay.level / 100
                to: overlay.level / 100
                duration: MMotion.reduceMotion || !overlay.plugged ? 0 : 600
                easing.type: Easing.OutCubic
            }
        }
        PauseAnimation {
            duration: 900
        }
        NumberAnimation {
            target: platter
            property: "opacity"
            to: 0
            duration: MMotion.reduceMotion ? 0 : 300
            easing.type: Easing.InCubic
        }
    }
}
