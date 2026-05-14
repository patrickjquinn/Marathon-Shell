import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Quick Settings slider.
//
// Row: 18 px icon + (label + value) + 4 px track with teal-gradient
// fill and a 14 px white thumb at the head. Halo'd thumb shadow.
//
// The slider is drag-only — caller wires `value` to a backend
// (brightness, volume). `from`/`to` are 0..100 by default.
Item {
    id: root

    property string iconName: "sun"
    property string label: ""
    property real value: 50          // 0..100
    property real from: 0
    property real to: 100

    signal moved(real value)           // user dragged — caller commits

    implicitHeight: 32

    readonly property real fraction: (value - from) / Math.max(1, to - from)

    Row {
        anchors.fill: parent
        spacing: 12

        // Icon
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: 18
            color: MColors.textSecondary
        }

        // Label / value + track.
        Item {
            width: parent.width - 18 - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height

            // Label row.
            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 0
                Text {
                    text: root.label
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightDemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: MTypography.trackingEyebrow
                }
                Item {
                    width: 6
                    height: 1
                }
                Text {
                    text: Math.round(root.value)
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightDemiBold
                    font.features: ({
                            "tnum": 1
                        })
                    anchors.right: parent.right
                }
            }

            // Track.
            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                height: 4
                radius: 2
                color: MColors.whiteOverlay08

                // Fill.
                Rectangle {
                    width: parent.width * root.fraction
                    height: parent.height
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: MColors.marathonTealDark
                        }
                        GradientStop {
                            position: 1
                            color: MColors.marathonTealBright
                        }
                    }
                }

                // Thumb.
                Rectangle {
                    id: thumb
                    width: 14
                    height: 14
                    radius: 7
                    color: "#ffffff"
                    border.width: 1
                    border.color: MColors.tealBorder
                    x: Math.max(0, Math.min(track.width - width, track.width * root.fraction - width / 2))
                    y: (track.height - height) / 2
                    z: 1
                }
            }

            MouseArea {
                anchors.fill: track
                anchors.topMargin: -10
                anchors.bottomMargin: -10
                onPressed: drag(mouseX)
                onPositionChanged: {
                    if (pressed)
                        drag(mouseX);
                }
                function drag(x) {
                    const f = Math.max(0, Math.min(1, x / track.width));
                    root.value = root.from + f * (root.to - root.from);
                    root.moved(root.value);
                }
            }
        }
    }
}
