import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects
import MarathonOS.Shell

// Marathon DS · Tab bar (ds-components.jsx:DSBars · marathon-tokens.css).
//
// 70 px tall, glass-tabbar over a 14 px blur, 1 px border-glass top
// edge + 1 px inner highlight. Up to 4 tabs, equal-width, flex
// column layout (icon 20 + 4 gap + label 12/500).
//
// Active state:
//   • top indicator: 2 px teal-gradient bar inset 12 % from each
//     side of the cell (not edge-to-edge).
//   • soft halo: 28 px tall radial-gradient ellipse at top, teal
//     at 0.28 alpha fading to transparent.
//   • color shifts: secondary → primary text + glyph.
Rectangle {
    id: root

    property int activeTab: 0
    property alias tabs: tabRepeater.model

    signal tabSelected(int index)

    // ── Shrink-on-scroll · iOS 26 / M3 Expressive chrome ───────────
    // Same scrollSource contract as MTopBar / MBottomBar — bind to
    // a Flickable to enable shrink-on-down, expand-on-up. Unbound =
    // legacy fixed-height.
    property var scrollSource: null
    property bool minimized: false
    property real _lastContentY: 0

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real barHeight: Math.round(70 * scaleFactor)
    readonly property real barHeightMin: Math.round(44 * scaleFactor)
    height: minimized ? barHeightMin : barHeight
    color: MColors.glassTabbar

    Behavior on height {
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

    // Top hairline divider per DS.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: MColors.borderGlass
    }
    // Inner highlight.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 1
        height: 1
        color: Qt.rgba(1, 1, 1, 0.05)
    }

    // ── Shared sliding indicator + halo ────────────────────────
    // ONE indicator + halo for the whole bar; x slides on a spring to
    // the active tab. iOS Control Center / M3E pattern: active state
    // slides, never swaps. Placed BEFORE the Row of tab buttons so
    // it paints UNDERNEATH the icons + labels (paint order = source
    // order for siblings with default z).
    readonly property real _tabWidth: tabRepeater.count > 0 ? root.width / tabRepeater.count : root.width

    Canvas {
        id: sharedGlow
        x: root.activeTab * root._tabWidth
        width: root._tabWidth
        height: Math.round(32 * root.scaleFactor)
        anchors.top: parent.top
        anchors.topMargin: 2

        Behavior on x {
            SpringAnimation {
                spring: MMotion.stiffnessSpatialFor("tap")
                damping: MMotion.dampingSpatialFor("tap")
                epsilon: MMotion.epsilon
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.save();
            const cx = width / 2;
            const cy = 0;
            const rx = width * 0.55;
            const ry = height;
            ctx.translate(cx, cy);
            ctx.scale(rx / ry, 1);
            const grad = ctx.createRadialGradient(0, 0, 0, 0, 0, ry);
            grad.addColorStop(0.0, "rgba(29, 233, 182, 0.28)");
            grad.addColorStop(0.70, "rgba(29, 233, 182, 0)");
            grad.addColorStop(1.0, "rgba(29, 233, 182, 0)");
            ctx.fillStyle = grad;
            ctx.fillRect(-ry, 0, ry * 2, ry);
            ctx.restore();
        }
    }

    Rectangle {
        id: sharedIndicator
        x: root.activeTab * root._tabWidth + root._tabWidth * 0.12
        width: root._tabWidth * 0.76
        anchors.top: parent.top
        height: Math.max(2, Math.round(2 * root.scaleFactor))

        Behavior on x {
            SpringAnimation {
                spring: MMotion.stiffnessSpatialFor("tap")
                damping: MMotion.dampingSpatialFor("tap")
                epsilon: MMotion.epsilon
            }
        }
        Behavior on width {
            SpringAnimation {
                spring: MMotion.stiffnessSpatialFor("tap")
                damping: MMotion.dampingSpatialFor("tap")
                epsilon: MMotion.epsilon
            }
        }

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: MColors.marathonTealDark
            }
            GradientStop {
                position: 0.5
                color: MColors.marathonTealBright
            }
            GradientStop {
                position: 1.0
                color: MColors.marathonTealDark
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: 0

        Repeater {
            id: tabRepeater

            Item {
                id: tabButton
                width: root.width / tabRepeater.count
                height: parent.height

                property bool selected: index === root.activeTab

                scale: tabMouseArea.pressed ? 0.96 : 1.0
                Behavior on scale {
                    SpringAnimation {
                        spring: MMotion.stiffnessSpatialFor("tap")
                        damping: MMotion.dampingSpatialFor("tap")
                        epsilon: MMotion.epsilon
                    }
                }

                // Per-delegate indicator + halo removed — the shared
                // sharedGlow/sharedIndicator above this Row handle it.
                Column {
                    anchors.centerIn: parent
                    spacing: Math.round(4 * root.scaleFactor)

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: modelData.icon || ""
                        size: Math.round(20 * root.scaleFactor)
                        color: tabButton.selected ? MColors.textPrimary : MColors.textSecondary
                        Behavior on color {
                            ColorAnimation {
                                duration: MMotion.quick
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.label || ""
                        color: tabButton.selected ? MColors.textPrimary : MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeCaption
                        font.weight: Font.Medium

                        Behavior on color {
                            ColorAnimation {
                                duration: MMotion.quick
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
