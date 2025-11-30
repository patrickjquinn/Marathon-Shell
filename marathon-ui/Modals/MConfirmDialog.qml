import QtQuick
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: root

    property string title: "Confirm"
    property string message: ""
    property string confirmText: "Confirm"
    property string cancelText: "Cancel"
    property bool showing: false

    signal confirmed
    signal cancelled

    anchors.fill: parent
    color: MColors.overlay
    visible: opacity > 0
    opacity: showing ? 1.0 : 0.0
    z: 10000

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.quick
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.cancelled()
    }

    Rectangle {
        id: dialogContainer
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 400)
        height: contentColumn.height + MSpacing.xl * 2

        color: MColors.bb10Elevated
        radius: MRadius.lg

        scale: root.showing ? 1.0 : 0.9

        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }

        border.width: 1
        border.color: MColors.borderGlass

        // Performant shadow for dialogs
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.leftMargin: -4
            anchors.rightMargin: -4
            anchors.bottomMargin: -12
            z: -1
            radius: parent.radius
            opacity: 0.5
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: "transparent"
                }
                GradientStop {
                    position: 0.2
                    color: Qt.rgba(0, 0, 0, 0.3)
                }
                GradientStop {
                    position: 1.0
                    color: Qt.rgba(0, 0, 0, 0.7)
                }
            }
        }

        layer.enabled: false

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: MColors.highlightSubtle
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: MSpacing.xl
            spacing: MSpacing.xl

            Text {
                text: root.title
                font.pixelSize: MTypography.sizeLarge
                font.weight: MTypography.weightDemiBold
                font.family: MTypography.fontFamily
                color: MColors.textPrimary
                width: parent.width
            }

            Text {
                text: root.message
                font.pixelSize: MTypography.sizeBody
                font.weight: MTypography.weightNormal
                font.family: MTypography.fontFamily
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Row {
                anchors.right: parent.right
                spacing: MSpacing.md

                MButton {
                    text: root.cancelText
                    variant: "secondary"
                    onClicked: {
                        root.showing = false;
                        root.cancelled();
                    }
                }

                MButton {
                    text: root.confirmText
                    variant: "primary"
                    onClicked: {
                        root.showing = false;
                        root.confirmed();
                    }
                }
            }
        }
    }

    function show() {
        showing = true;
    }

    function hide() {
        showing = false;
    }
}
