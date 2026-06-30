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

    // ── Shrink-on-scroll · iOS 26 / Material 3 Expressive chrome ──
    // When `scrollSource` is bound to a Flickable/ListView, the bar
    // shrinks on downward scroll (gives way to content) and fluidly
    // expands on upward scroll. Unbound = legacy fixed-height
    // behaviour; callers opt in per-page by setting scrollSource.
    //
    //   page MPage {
    //       MTopBar { scrollSource: scrollView.flickableItem }
    //   }
    //
    // Threshold (8 px) avoids twitchy state flips from finger jitter.
    // Activation guard (cy > 20) keeps the bar full-height during
    // rubber-band overshoot at the top of the list.
    property var scrollSource: null
    property bool minimized: false
    property real _lastContentY: 0

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real barHeight: Math.round(96 * scaleFactor)
    readonly property real barHeightMin: Math.round(60 * scaleFactor)
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    // NOT readonly — Behavior on titleFontSize below interpolates the
    // value when `minimized` flips, which requires the property to be
    // writable. The binding still drives it; the Behavior just shapes
    // the transition.
    property real titleFontSize: Math.round((minimized ? 20 : 34) * scaleFactor)
    readonly property real titleLetterSpacing: -0.8 * scaleFactor

    height: minimized ? barHeightMin : barHeight
    color: MColors.glassTitlebar

    Behavior on height {
        SpringAnimation {
            spring: MMotion.stiffnessSpatialFor("modal")
            damping: MMotion.dampingSpatialFor("modal")
            epsilon: MMotion.epsilon
        }
    }
    Behavior on titleFontSize {
        SpringAnimation {
            spring: MMotion.stiffnessSpatialFor("modal")
            damping: MMotion.dampingSpatialFor("modal")
            epsilon: MMotion.epsilon
        }
    }

    Connections {
        target: root.scrollSource
        function onContentYChanged() {
            if (!root.scrollSource)
                return;
            var cy = root.scrollSource.contentY;
            if (cy > root._lastContentY + 8 && cy > 20)
                root.minimized = true;
            else if (cy < root._lastContentY - 8)
                root.minimized = false;
            root._lastContentY = cy;
        }
    }

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
            font.pixelSize: MTypography.sizeTitle2
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
