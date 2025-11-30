import QtQuick
import QtQuick.Effects
import MarathonUI.Theme
import MarathonUI.Core
import MarathonOS.Shell

Item {
    id: root

    property bool checked: false
    property string text: ""
    property bool disabled: false
    property string state: "default"

    signal toggled(bool checked)
    signal clicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real checkboxSize: Math.round(24 * scaleFactor)
    readonly property real iconSize: Math.round(16 * scaleFactor)
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))

    implicitWidth: row.implicitWidth
    implicitHeight: MSpacing.touchTargetMin

    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.checked: checked
    Accessible.onPressAction: if (!disabled)
        toggle()

    Keys.onSpacePressed: if (!disabled)
        toggle()
    Keys.onReturnPressed: if (!disabled)
        toggle()

    function toggle() {
        if (!disabled && state === "default") {
            checked = !checked;
            toggled(checked);
            MHaptics.lightImpact();
        }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: MSpacing.md

        Rectangle {
            id: checkboxRect
            width: checkboxSize
            height: checkboxSize
            radius: MRadius.sm
            anchors.verticalCenter: parent.verticalCenter

            color: {
                if (root.disabled)
                    return MColors.bb10Surface;
                if (root.checked)
                    return MColors.marathonTeal;
                if (mouseArea.pressed)
                    return MColors.highlightSubtle;
                return "transparent";
            }

            border.width: root.checked ? 0 : borderWidth
            border.color: root.disabled ? MColors.textHint : MColors.borderGlass

            scale: mouseArea.pressed ? 0.92 : 1.0

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.sm
                }
            }

            Behavior on scale {
                SpringAnimation {
                    spring: MMotion.springMedium
                    damping: MMotion.dampingMedium
                    epsilon: MMotion.epsilon
                }
            }

            Behavior on border.color {
                ColorAnimation {
                    duration: MMotion.sm
                }
            }

            Icon {
                id: checkIcon
                anchors.centerIn: parent
                name: "check"
                size: iconSize
                color: MColors.textOnAccent
                visible: root.checked
                scale: root.checked ? 1 : 0

                Behavior on scale {
                    SpringAnimation {
                        spring: MMotion.springLight
                        damping: MMotion.dampingLight
                        epsilon: MMotion.epsilon
                    }
                }
            }

            layer.enabled: root.checked && !root.disabled
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: MColors.marathonTeal
                shadowVerticalOffset: 0
                shadowHorizontalOffset: 0
                shadowBlur: 0.4
                blurMax: 8
                paddingRect: Qt.rect(0, 0, 0, 0)
            }
        }

        Text {
            text: root.text
            color: root.disabled ? MColors.textHint : MColors.textPrimary
            font.pixelSize: MTypography.sizeBody
            font.family: MTypography.fontFamily
            font.weight: MTypography.weightNormal
            anchors.verticalCenter: parent.verticalCenter
            visible: root.text !== ""

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.sm
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: !root.disabled && root.state === "default"
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: {
            root.toggle();
            root.clicked();
        }
    }
}
