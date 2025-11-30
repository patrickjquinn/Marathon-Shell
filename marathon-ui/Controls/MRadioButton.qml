import QtQuick
import QtQuick.Effects
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects
import MarathonOS.Shell

Item {
    id: root

    property bool checked: false
    property string text: ""
    property bool disabled: false
    property string groupName: ""
    property variant value: undefined

    signal toggled(bool checked)
    signal clicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real radioSize: Math.round(24 * scaleFactor)
    readonly property real radioRadius: radioSize / 2
    readonly property real innerSize: Math.round(12 * scaleFactor)
    readonly property real innerRadius: innerSize / 2
    readonly property real borderWidth: Math.max(1, Math.round(2 * scaleFactor))

    implicitWidth: row.implicitWidth
    implicitHeight: MSpacing.touchTargetMin

    Accessible.role: Accessible.RadioButton
    Accessible.name: text
    Accessible.checked: checked
    Accessible.onPressAction: if (!disabled)
        select()

    Keys.onSpacePressed: if (!disabled)
        select()
    Keys.onReturnPressed: if (!disabled)
        select()

    function select() {
        if (!disabled && !checked) {
            checked = true;
            toggled(true);
            MHaptics.lightImpact();

            if (groupName !== "" && parent) {
                for (var i = 0; i < parent.children.length; i++) {
                    var child = parent.children[i];
                    if (child !== root && child.hasOwnProperty("groupName") && child.groupName === groupName && child.hasOwnProperty("checked")) {
                        child.checked = false;
                    }
                }
            }
        }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: MSpacing.md

        Rectangle {
            id: radioRect
            width: radioSize
            height: radioSize
            radius: radioRadius
            anchors.verticalCenter: parent.verticalCenter

            color: {
                if (root.disabled)
                    return MColors.bb10Surface;
                if (mouseArea.pressed)
                    return MColors.highlightSubtle;
                return "transparent";
            }

            border.width: borderWidth
            border.color: {
                if (root.disabled)
                    return MColors.textHint;
                if (root.checked)
                    return MColors.marathonTeal;
                return MColors.borderGlass;
            }

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

            Rectangle {
                id: innerCircle
                anchors.centerIn: parent
                width: innerSize
                height: innerSize
                radius: innerRadius
                color: MColors.marathonTeal
                visible: root.checked && !root.disabled
                scale: root.checked ? 1 : 0

                Behavior on scale {
                    SpringAnimation {
                        spring: MMotion.springLight
                        damping: MMotion.dampingLight
                        epsilon: MMotion.epsilon
                    }
                }

                layer.enabled: true
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
        enabled: !root.disabled
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true

        onClicked: {
            root.select();
            root.clicked();
        }
    }
}
