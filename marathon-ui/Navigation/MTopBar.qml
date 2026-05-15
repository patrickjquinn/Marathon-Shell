import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

// Marathon DS · Top bar (ds-components.jsx:DSBars).
//
// Height 96 px. Glass-titlebar background, 1 px border-glass bottom
// edge plus 1 px w-06 inner highlight. Title is 34/200 Sora with
// -0.8 letter-spacing, anchored to the BOTTOM of the bar 16 px above
// the lower edge — flex-end alignment per DS. Actions row sits on
// the same baseline on the right.
Rectangle {
    id: root

    property string title: ""
    property alias actions: actionsItem.children
    property bool showBack: false
    signal backClicked

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real barHeight: Math.round(96 * scaleFactor)
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real titleFontSize: Math.round(34 * scaleFactor)
    readonly property real titleLetterSpacing: -0.8 * scaleFactor

    height: barHeight
    color: MColors.glassTitlebar

    // Bottom hairline divider.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: borderWidth
        color: MColors.borderGlass
    }

    // Inset top highlight per DS card edge treatment.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: borderWidth
        color: Qt.rgba(1, 1, 1, 0.06)
    }

    // Optional back chevron — DS calls it out as the left-side
    // affordance when present, sitting at the same baseline as title.
    Item {
        id: backHit
        visible: root.showBack
        width: visible ? 36 : 0
        height: 36
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12

        Text {
            anchors.centerIn: parent
            text: "‹"        // single left guillemet — chevron-left glyph
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: 28
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.backClicked()
        }
    }

    Text {
        id: titleText
        anchors.left: backHit.visible ? backHit.right : parent.left
        anchors.leftMargin: backHit.visible ? 4 : 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        text: root.title
        color: MColors.textPrimary
        font.pixelSize: titleFontSize
        font.weight: MTypography.weightExtraLight     // 200 per DS
        font.family: MTypography.fontFamily
        font.letterSpacing: titleLetterSpacing
    }

    Row {
        id: actionsItem
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        spacing: 14
    }
}
