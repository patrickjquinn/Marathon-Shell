import MarathonOS.Shell
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

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

    // Opacity rides the effects family — colour/opacity must not
    // ring per M3 Expressive. Spring + critical damping gives the
    // overlay a soft fade-in/out without the abrupt cut of a fixed-
    // duration NumberAnimation.
    Behavior on opacity {
        SpringAnimation {
            spring: MMotion.stiffnessEffectsFor("modal")
            damping: MMotion.dampingEffectsFor("modal")
            epsilon: MMotion.epsilon
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

        // Sheet container — was opaque MColors.bb10Elevated; now
        // glass-blurred via MGlass underneath. Keeps the elevated
        // chroma but lets the surface read as a panel over content
        // instead of a hard plate.
        color: "transparent"
        radius: MRadius.xl

        MGlass {
            id: sheetGlass
            anchors.fill: parent
            sourceItem: root.parent
            blurMaxRadius: MBlur.blurFor("sheet")
            tint: Qt.rgba(MColors.bb10Elevated.r, MColors.bb10Elevated.g, MColors.bb10Elevated.b, 0.78)
            borderColor: MColors.borderGlass
            topHairline: false
            z: -1
        }

        y: root.showing ? 0 : height

        Behavior on y {
            SpringAnimation {
                spring: MMotion.stiffnessSpatialFor("sheet")
                damping: MMotion.dampingSpatialFor("sheet")
                epsilon: MMotion.epsilonSpatial
            }
        }

        border.width: 1
        border.color: MColors.borderGlass

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

        MTopHairline {
            radius: parent.radius
            color: MColors.highlightSubtle
            lineWidth: 1
        }

        Rectangle {
            id: handle
            anchors.top: parent.top
            anchors.topMargin: MSpacing.md
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(40 * scaleFactor)
            height: Math.round(4 * scaleFactor)
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

    function open() {
        showing = true;
    }

    function close() {
        showing = false;
        closed();
    }

    function show() {
        open();
    }

    function hide() {
        close();
    }
}
