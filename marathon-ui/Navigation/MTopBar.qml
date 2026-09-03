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
    // Leading-content slot — injected just RIGHT of the back chevron
    // and LEFT of the title. Use for an avatar pill (chat header),
    // contact monogram, account swatch, etc. Empty by default so
    // standard MTopBar callers see no change.
    property alias leadingContent: leadingItem.children
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
            epsilon: MMotion.epsilonSpatial
        }
    }
    Behavior on titleFontSize {
        SpringAnimation {
            spring: MMotion.stiffnessSpatialFor("modal")
            damping: MMotion.dampingSpatialFor("modal")
            epsilon: MMotion.epsilonSpatial
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
        height: root.borderWidth
        color: MColors.borderGlass
    }

    // Inset top highlight per DS card edge treatment.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.borderWidth
        color: Qt.rgba(1, 1, 1, 0.06)
    }

    // Optional back chevron — DS calls it out as the left-side
    // affordance when present, sitting at the same baseline as title.
    // Every inset below is scaled. barHeight already was (96 * scaleFactor)
    // while the margins, the back button and the action spacing were raw
    // pixels — so raising userScaleFactor grew the bar but left its
    // contents pinned to the same physical offsets. At 1.50 the title
    // crowded the bottom edge and the back target stayed 36 px, under the
    // 44 px minimum. Same failure mode as the OOBE clipping: a container
    // that scales around children that do not.
    readonly property real insetSm: Math.round(8 * scaleFactor)
    readonly property real insetMd: Math.round(12 * scaleFactor)
    readonly property real insetLg: Math.round(16 * scaleFactor)
    readonly property real insetXl: Math.round(20 * scaleFactor)
    // Floor at 44 px: the minimum touch target, regardless of scale.
    readonly property real backSize: Math.max(44, Math.round(36 * scaleFactor))

    Item {
        id: backHit
        visible: root.showBack
        width: visible ? root.backSize : 0
        height: root.backSize
        anchors.left: parent.left
        anchors.leftMargin: root.insetMd
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.insetMd

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

    // Leading slot — sits between the back chevron and the title.
    // Caller-injected items (e.g. an avatar pill) anchor inside this
    // Row.
    Row {
        id: leadingItem
        anchors.left: backHit.visible ? backHit.right : parent.left
        anchors.leftMargin: backHit.visible ? root.insetSm : root.insetXl
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(14 * root.scaleFactor)
        spacing: root.insetSm
    }

    Text {
        id: titleText
        anchors.left: leadingItem.children.length > 0 ? leadingItem.right : (backHit.visible ? backHit.right : parent.left)
        anchors.leftMargin: leadingItem.children.length > 0
                            ? Math.round(10 * root.scaleFactor)
                            : (backHit.visible ? Math.round(4 * root.scaleFactor) : root.insetXl)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.insetLg
        text: root.title
        color: MColors.textPrimary
        font.pixelSize: root.titleFontSize
        font.weight: MTypography.weightExtraLight     // 200 per DS
        font.family: MTypography.fontFamily
        font.letterSpacing: root.titleLetterSpacing
    }

    Row {
        id: actionsItem
        anchors.right: parent.right
        anchors.rightMargin: root.insetXl
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.insetXl
        spacing: 14
    }
}
