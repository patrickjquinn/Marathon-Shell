import QtQuick
import QtQuick.Effects
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects
import MarathonOS.Shell

Rectangle {
    id: root

    property bool showBack: true
    property string backLabel: "Back"
    property int activeAction: 0
    property alias actions: actionRepeater.model
    property alias signatureButton: sigButton
    property bool showOverflow: true

    signal backClicked
    signal actionSelected(int index)
    signal signatureClicked
    signal overflowClicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    height: Math.round(108 * scaleFactor)
    color: MColors.glassActionbar

    border.width: 1
    border.color: MColors.borderGlass

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -1
        anchors.leftMargin: -1
        anchors.rightMargin: -1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.06)
        z: 1
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -Math.round(16 * root.scaleFactor)
        height: Math.round(16 * root.scaleFactor)
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(0, 0, 0, 0.4)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: MSpacing.sm

        Rectangle {
            id: backButton
            visible: root.showBack
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(72 * root.scaleFactor)
            height: Math.round(44 * root.scaleFactor)
            radius: MRadius.md
            color: "transparent"

            scale: backMouseArea.pressed ? 0.96 : 1.0

            Behavior on scale {
                SpringAnimation {
                    spring: MMotion.springMedium
                    damping: MMotion.dampingMedium
                    epsilon: MMotion.epsilon
                }
            }

            Row {
                anchors.centerIn: parent
                // DS button icon-to-text gap = 8 (matches MButton's contentRow).
                spacing: Math.round(8 * root.scaleFactor)

                Text {
                    text: "◀"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.backLabel
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: -Math.round(12 * root.scaleFactor)
                anchors.top: parent.top
                anchors.topMargin: parent.height * 0.2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.height * 0.2
                width: 1
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(1, 1, 1, 0.02)
                    }
                }
            }

            MouseArea {
                id: backMouseArea
                anchors.fill: parent
                onPressed: MHaptics.lightImpact()
                onClicked: root.backClicked()
            }
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: {
                var totalWidth = parent.width - parent.anchors.leftMargin - parent.anchors.rightMargin;
                var usedWidth = (root.showBack ? backButton.width : 0) + Math.round(68 * root.scaleFactor) + (root.showOverflow ? overflowButton.width : 0);
                var spacingCount = (root.showBack ? 1 : 0) + 1 + (root.showOverflow ? 1 : 0);
                return totalWidth - usedWidth - (parent.spacing * spacingCount);
            }

            Row {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    id: actionRepeater

                    Rectangle {
                        id: actionTab
                        width: parent.width / actionRepeater.count
                        height: parent.height
                        color: isActive ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                        property bool isActive: index === root.activeAction

                        scale: actionMouseArea.pressed ? 0.96 : 1.0

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

                        Rectangle {
                            id: topIndicator
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.max(2, Math.round(3 * root.scaleFactor))

                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: isActive ? MColors.marathonTealDark : Qt.rgba(1, 1, 1, 0.12)
                                }
                                GradientStop {
                                    position: 0.5
                                    color: isActive ? MColors.marathonTeal : Qt.rgba(1, 1, 1, 0.12)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: isActive ? MColors.marathonTealDark : Qt.rgba(1, 1, 1, 0.12)
                                }
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: topIndicator.horizontalCenter
                            anchors.top: topIndicator.bottom
                            width: topIndicator.width
                            height: Math.round(35 * root.scaleFactor)
                            visible: isActive
                            opacity: 0.6
                            gradient: Gradient {
                                GradientStop {
                                    position: 0.0
                                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.18)
                                }
                                GradientStop {
                                    position: 0.25
                                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.10)
                                }
                                GradientStop {
                                    position: 0.5
                                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.05)
                                }
                                GradientStop {
                                    position: 0.75
                                    color: Qt.rgba(0, 191 / 255, 165 / 255, 0.02)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: "transparent"
                                }
                            }
                        }

                        Rectangle {
                            visible: isActive
                            anchors.right: parent.right
                            anchors.rightMargin: -Math.round(8 * root.scaleFactor)
                            anchors.top: parent.top
                            anchors.topMargin: -Math.round(2 * root.scaleFactor)
                            anchors.bottom: parent.bottom
                            width: Math.round(12 * root.scaleFactor)
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop {
                                    position: 0.0
                                    color: Qt.rgba(0, 0, 0, 0.4)
                                }
                                GradientStop {
                                    position: 0.5
                                    color: Qt.rgba(0, 0, 0, 0.15)
                                }
                                GradientStop {
                                    position: 1.0
                                    color: "transparent"
                                }
                            }
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blurMax: MBlur.xs
                            }
                            opacity: 0.4
                        }

                        Column {
                            anchors.centerIn: parent
                            // DS tab icon-to-label gap = 6 (vertical stack
                            // intentionally tighter than the horizontal
                            // button gap — closer reads as one item).
                            spacing: Math.round(6 * root.scaleFactor)

                            Icon {
                                name: modelData.icon || ""
                                size: Math.round(22 * root.scaleFactor)
                                color: isActive ? MColors.textPrimary : MColors.textSecondary
                                anchors.horizontalCenter: parent.horizontalCenter

                                Behavior on color {
                                    ColorAnimation {
                                        duration: MMotion.sm
                                    }
                                }
                            }

                            Text {
                                text: modelData.label || ""
                                color: isActive ? MColors.textPrimary : MColors.textSecondary
                                font.pixelSize: MTypography.sizeXSmall
                                font.weight: Font.Normal
                                font.family: MTypography.fontFamily
                                anchors.horizontalCenter: parent.horizontalCenter

                                Behavior on color {
                                    ColorAnimation {
                                        duration: MMotion.sm
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: actionMouseArea
                            anchors.fill: parent

                            onPressed: MHaptics.lightImpact()
                            onClicked: {
                                root.activeAction = index;
                                root.actionSelected(index);
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(68 * root.scaleFactor)
            height: Math.round(68 * root.scaleFactor)
            radius: 34
            color: "transparent"
            border.width: 3
            border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)

            Rectangle {
                id: sigButton
                anchors.centerIn: parent
                width: Math.round(62 * root.scaleFactor)
                height: Math.round(62 * root.scaleFactor)
                radius: 31

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0.0
                        color: MColors.marathonTealBright
                    }
                    GradientStop {
                        position: 0.5
                        color: MColors.marathonTeal
                    }
                    GradientStop {
                        position: 1.0
                        color: MColors.marathonTealDark
                    }
                }

                scale: sigMouseArea.pressed ? 0.96 : 1.0

                Behavior on scale {
                    SpringAnimation {
                        spring: MMotion.springLight
                        damping: MMotion.dampingLight
                        epsilon: MMotion.epsilon
                    }
                }

                MTopHairline {
                    radius: parent.radius
                    color: Qt.rgba(1, 1, 1, 0.1)
                    lineWidth: 1
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: parent.radius - 2
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: Qt.rgba(1, 1, 1, 0.3)
                        }
                        GradientStop {
                            position: 0.5
                            color: "transparent"
                        }
                    }
                    opacity: 0.6
                }

                Icon {
                    name: "plus"
                    size: Math.round(28 * root.scaleFactor)
                    color: MColors.textOnAccent
                    anchors.centerIn: parent
                }

                MouseArea {
                    id: sigMouseArea
                    anchors.fill: parent
                    onPressed: MHaptics.mediumImpact()
                    onClicked: root.signatureClicked()
                }
            }
        }

        Rectangle {
            id: overflowButton
            visible: root.showOverflow
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(54 * root.scaleFactor)
            height: parent.height
            radius: MRadius.md
            color: "transparent"

            Text {
                text: "•••"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                anchors.centerIn: parent
            }

            MouseArea {
                id: overflowMouseArea
                anchors.fill: parent
                onPressed: MHaptics.lightImpact()
                onClicked: root.overflowClicked()
            }
        }
    }
}
