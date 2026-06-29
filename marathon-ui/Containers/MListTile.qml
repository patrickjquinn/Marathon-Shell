import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Effects

Rectangle {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property string title: ""
    property string subtitle: ""
    property alias leading: leadingContent.data
    property alias trailing: trailingContent.data
    property bool clickable: false
    property bool showDivider: true
    property int animationIndex: 0

    signal clicked

    width: parent ? parent.width : 400
    height: Math.round(56 * scaleFactor)
    color: mouseArea.pressed ? MColors.highlightSubtle : "transparent"
    scale: (root.clickable && mouseArea.pressed) ? 0.97 : 1.0
    clip: true

    Accessible.role: clickable ? Accessible.Button : Accessible.ListItem
    Accessible.name: title
    Accessible.description: subtitle
    Accessible.onPressAction: if (clickable)
        clicked()

    Keys.onReturnPressed: if (clickable)
        clicked()
    Keys.onSpacePressed: if (clickable)
        clicked()

    Behavior on color {
        ColorAnimation {
            duration: MMotion.sm
        }
    }

    // Staggered entrance — wired through MEntrance so list rows fade
    // up with a subtle indexed delay. animationIndex has been a
    // declared-but-unconsumed property for many revisions; this is
    // the consumer.
    MEntrance {
        target: root
        index: root.animationIndex
    }

    // Subtle press scale on clickable rows. Compositor-only — no
    // layout reflow. Spring tuned to the microPress role.
    transformOrigin: Item.Center
    Behavior on scale {
        enabled: root.clickable && !MMotion.reduceMotion
        SpringAnimation {
            spring: MMotion.springFor("microPress")
            damping: MMotion.dampingFor("microPress")
            epsilon: MMotion.epsilon
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: MSpacing.md
        clip: true

        Item {
            id: leadingContent
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(childrenRect.width, 48)
            height: childrenRect.height
            clip: true
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - leadingContent.width - trailingContent.width - (parent.spacing * 2) - parent.anchors.leftMargin - parent.anchors.rightMargin
            spacing: 2
            clip: true

            Text {
                text: root.title
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeBody
                font.weight: MTypography.weightNormal
                font.family: MTypography.fontFamily
                width: parent.width
                elide: Text.ElideRight
            }

            Text {
                text: root.subtitle
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.weight: MTypography.weightNormal
                font.family: MTypography.fontFamily
                visible: root.subtitle !== ""
                width: parent.width
                elide: Text.ElideRight
            }
        }

        Item {
            id: trailingContent
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(childrenRect.width, 100)
            height: childrenRect.height
            clip: true
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: MSpacing.md
        height: 1
        color: MColors.borderSubtle
        visible: root.showDivider
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        enabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: root.clickable

        onClicked: {
            root.clicked();
            MHaptics.lightImpact();
        }
    }
}
