import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: root

    property string title: ""
    property alias content: contentItem.data
    property bool showing: false

    signal closed
    signal accepted

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real shadowTopMargin: Math.max(1, Math.round(8 * scaleFactor))
    readonly property real shadowLRMargin: Math.max(1, Math.round(4 * scaleFactor))
    readonly property real shadowBottomMargin: Math.max(1, Math.round(12 * scaleFactor))
    readonly property real innerMargin: Math.max(1, Math.round(1 * scaleFactor))

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
        id: modalContainer
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.9, 600)
        height: Math.min(parent.height * 0.8, 700)

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

        border.width: borderWidth
        border.color: MColors.borderGlass

        // Performant shadow for modals (looks great, runs smooth on PinePhone)
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: shadowTopMargin
            anchors.leftMargin: -shadowLRMargin
            anchors.rightMargin: -shadowLRMargin
            anchors.bottomMargin: -shadowBottomMargin
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
            anchors.margins: innerMargin
            radius: parent.radius > innerMargin ? parent.radius - innerMargin : 0
            color: "transparent"
            border.width: borderWidth
            border.color: MColors.highlightSubtle
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        Column {
            anchors.fill: parent
            anchors.margins: MSpacing.xl
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
