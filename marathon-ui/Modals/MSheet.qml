import QtQuick
import MarathonUI.Theme

Rectangle {
    id: root

    property string title: ""
    property alias content: contentItem.data
    property bool showing: false
    property real sheetHeight: 0.6

    signal closed

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
        onClicked: root.closed()
    }

    Rectangle {
        id: sheetContainer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * root.sheetHeight

        color: MColors.bb10Elevated
        radius: MRadius.xl

        y: root.showing ? 0 : height

        Behavior on y {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }

        border.width: 1
        border.color: MColors.borderGlass

        // Performant shadow for sheets (upward shadow)
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: -4
            anchors.leftMargin: -3
            anchors.rightMargin: -3
            anchors.bottomMargin: 0
            z: -1
            radius: parent.radius
            opacity: 0.5
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(0, 0, 0, 0.7)
                }
                GradientStop {
                    position: 0.3
                    color: Qt.rgba(0, 0, 0, 0.3)
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
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

        Rectangle {
            id: handle
            anchors.top: parent.top
            anchors.topMargin: MSpacing.md
            anchors.horizontalCenter: parent.horizontalCenter
            width: 40
            height: 4
            radius: 2
            color: MColors.textTertiary
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            anchors.fill: parent
            anchors.margins: MSpacing.xl
            anchors.topMargin: MSpacing.xl + MSpacing.lg
            spacing: MSpacing.lg

            Text {
                text: root.title
                font.pixelSize: MTypography.sizeXLarge
                font.weight: MTypography.weightDemiBold
                font.family: MTypography.fontFamily
                color: MColors.textPrimary
                visible: root.title !== ""
                width: parent.width
            }

            Item {
                id: contentItem
                width: parent.width
                height: parent.height - (root.title !== "" ? (MTypography.sizeXLarge + MSpacing.lg) : 0)
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
