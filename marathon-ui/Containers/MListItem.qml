import QtQuick
import QtQuick.Effects
import MarathonUI.Theme

Rectangle {
    id: root

    property alias thumb: thumbRect
    required property string title
    property string subtitle: ""
    property string time: ""
    property int animationIndex: 0  // For staggered entrance animation
    property bool enableEntrance: true

    signal clicked

    width: parent.width
    height: 88
    color: pressed ? MColors.highlightSubtle : "transparent"

    property bool pressed: false
    property real entranceProgress: enableEntrance ? 0 : 1

    // Staggered entrance animation using transform instead of y position
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
            width: 72
            height: 72
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
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.4)
                shadowVerticalOffset: 1
                shadowBlur: 0.2
                blurMax: 2
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.03)
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - thumbRect.width - MSpacing.lg - timeText.width - MSpacing.lg
            spacing: 4

            Text {
                id: titleText
                text: root.title
                color: MColors.textPrimary
                font.pixelSize: 17
                font.weight: Font.Normal
                font.family: MTypography.fontFamily
                width: parent.width
                elide: Text.ElideRight
            }

            Text {
                id: subtitleText
                text: root.subtitle
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.weight: Font.Light
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
