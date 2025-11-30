import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects

Rectangle {
    id: root

    property int activeTab: 0
    property alias tabs: tabRepeater.model

    signal tabSelected(int index)

    height: 70
    color: MColors.glassTabbar

    border.width: 1
    border.color: MColors.borderGlass

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -1
        anchors.leftMargin: -1
        anchors.rightMargin: -1
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.05)
        z: 1
    }

    Row {
        anchors.fill: parent
        spacing: 0

        Repeater {
            id: tabRepeater

            Rectangle {
                id: tabButton
                width: root.width / tabRepeater.count
                height: parent.height
                color: index === root.activeTab ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                property bool selected: index === root.activeTab

                scale: tabMouseArea.pressed ? 0.96 : 1.0

                Behavior on color {
                    ColorAnimation {
                        duration: MMotion.sm
                    }
                }

                Behavior on scale {
                    SpringAnimation {
                        spring: MMotion.springMedium
                        damping: MMotion.springMedium
                        epsilon: MMotion.epsilon
                    }
                }

                Rectangle {
                    id: indicatorRect
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 3

                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: selected ? MColors.marathonTealDark : Qt.rgba(1, 1, 1, 0.12)
                        }
                        GradientStop {
                            position: 0.5
                            color: selected ? MColors.marathonTeal : Qt.rgba(1, 1, 1, 0.12)
                        }
                        GradientStop {
                            position: 1.0
                            color: selected ? MColors.marathonTealDark : Qt.rgba(1, 1, 1, 0.12)
                        }
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: indicatorRect.horizontalCenter
                    anchors.top: indicatorRect.bottom
                    width: indicatorRect.width
                    height: 35
                    visible: selected
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
                    visible: selected
                    anchors.right: parent.right
                    anchors.rightMargin: -8
                    anchors.top: parent.top
                    anchors.topMargin: -2
                    anchors.bottom: parent.bottom
                    width: 12
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
                    opacity: 0.4
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 6

                    Icon {
                        name: modelData.icon || ""
                        size: 20
                        color: selected ? MColors.textPrimary : MColors.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter

                        Behavior on color {
                            ColorAnimation {
                                duration: MMotion.sm
                            }
                        }
                    }

                    Text {
                        text: modelData.label || ""
                        color: selected ? MColors.textPrimary : MColors.textSecondary
                        font.pixelSize: MTypography.sizeSmall
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
                    id: tabMouseArea
                    anchors.fill: parent

                    onPressed: MHaptics.lightImpact()
                    onClicked: {
                        root.activeTab = index;
                        root.tabSelected(index);
                    }
                }
            }
        }
    }
}
