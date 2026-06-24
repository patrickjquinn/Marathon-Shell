import MarathonOS.Shell
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

Rectangle {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property alias thumb: thumbRect
    required property string title
    property string subtitle: ""
    property string time: ""
    property int animationIndex: 0
    property bool enableEntrance: true

    signal clicked

    width: parent.width
    height: Math.round(88 * scaleFactor)
    color: pressed ? MColors.highlightSubtle : "transparent"

    property bool pressed: false
    property real entranceProgress: enableEntrance ? 0 : 1

    opacity: entranceProgress
    transform: Translate {
        y: (1 - entranceProgress) * 20
    }

    Component.onCompleted: {
        if (enableEntrance) {
            entranceDelay.start();
        }
    }

    Timer {
        id: entranceDelay
        interval: animationIndex * MMotion.staggerShort
        running: false
        onTriggered: {
            root.entranceProgress = 1;
        }
    }

    Behavior on entranceProgress {
        enabled: enableEntrance
        NumberAnimation {
            duration: MMotion.moderate
            easing.bezierCurve: MMotion.easingDecelerateCurve
        }
    }

    Behavior on opacity {
        enabled: enableEntrance
        NumberAnimation {
            duration: MMotion.quick
            easing.bezierCurve: MMotion.easingDecelerateCurve
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: MMotion.sm
        }
    }

    Rectangle {
        id: hoverOverlay
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: Qt.rgba(0, 191 / 255, 165 / 255, 0.03)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
        opacity: mouseArea.containsMouse ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.sm
            }
        }
    }

    Rectangle {
        id: pressRipple
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(0, 191 / 255, 165 / 255, 0.12)
            }
            GradientStop {
                position: 0.6
                color: "transparent"
            }
        }
        opacity: root.pressed ? 1 : 0
        scale: root.pressed ? 1 : 0.8

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.quick
            }
        }

        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springLight
                damping: MMotion.dampingLight
                epsilon: MMotion.epsilon
            }
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.xl
        anchors.rightMargin: MSpacing.xl
        spacing: MSpacing.lg

        Rectangle {
            id: thumbRect
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(72 * scaleFactor)
            height: Math.round(72 * scaleFactor)
            radius: MRadius.lg
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: MColors.bb10Surface
                }
                GradientStop {
                    position: 1.0
                    color: MColors.bb10Elevated
                }
            }
            border.width: 1
            border.color: MColors.borderSubtle

            layer.enabled: true
            layer.smooth: true
            layer.samples: Constants.layerSamples
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.4)
                shadowVerticalOffset: 1
                shadowBlur: 0.2
                blurMax: 2
            }

            MTopHairline {
                radius: parent.radius
                color: Qt.rgba(1, 1, 1, 0.03)
                lineWidth: 1
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - thumbRect.width - MSpacing.lg - timeText.width - MSpacing.lg
            spacing: Math.round(4 * scaleFactor)

            Text {
                id: titleText
                // DS Headline — 17/600 per MTypography role default.
                // Was 17/400 (Normal) which read as a generic Body label
                // and made every list row feel flat. DS calls the title
                // role "Headline" for a reason: it carries the row.
                text: root.title
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeHeadline
                font.weight: MTypography.weightDemiBold
                font.letterSpacing: MTypography.trackingHeadline
                font.family: MTypography.fontFamily
                width: parent.width
                elide: Text.ElideRight
            }

            Text {
                id: subtitleText
                text: root.subtitle
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeFootnote
                font.weight: MTypography.weightRegular
                font.family: MTypography.fontFamily
                width: parent.width
                elide: Text.ElideRight
            }
        }

        Text {
            id: timeText
            text: root.time
            anchors.verticalCenter: parent.verticalCenter
            color: MColors.marathonTeal
            font.pixelSize: MTypography.sizeXSmall
            font.weight: Font.Medium
            font.family: MTypography.fontFamily
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: MColors.borderSubtle
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property real mouseX: 0
        property real mouseY: 0

        onPressed: function (mouse) {
            mouseX = mouse.x;
            mouseY = mouse.y;
            root.pressed = true;
        }

        onReleased: root.pressed = false
        onCanceled: root.pressed = false

        onClicked: root.clicked()
    }
}
