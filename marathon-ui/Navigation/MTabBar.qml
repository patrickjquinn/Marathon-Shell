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

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    height: Math.round(70 * scaleFactor)
    color: MColors.glassTabbar

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
                        spring: MMotion.springMedium
                        damping: MMotion.springMedium
                        epsilon: MMotion.epsilon
                    }
                }

                // Active indicator — 2 px teal-gradient bar, inset 12 %
                // from each side per marathon-tokens.css .tab.active::before.
                Rectangle {
                    visible: tabButton.selected
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.76
                    height: Math.max(2, Math.round(2 * root.scaleFactor))
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

                // Active halo — radial-gradient ellipse anchored at the
                // top centre, fading to transparent. JSX/CSS spec:
                //   radial-gradient(ellipse at center top,
                //                   rgba(29,233,182,0.28), transparent 70%)
                //
                // Implemented with a Canvas so the falloff is a real
                // ellipse and not a stack of rectangles. The Canvas only
                // exists while the tab is selected, so the runtime cost
                // is one paint when activeTab changes.
                Canvas {
                    id: glowCanvas
                    visible: tabButton.selected
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: Math.round(32 * root.scaleFactor)
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onVisibleChanged: if (visible)
                        requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        // Build an elliptical radial gradient by scaling
                        // the y axis. Canvas only supports circular
                        // radial gradients natively; the scale trick
                        // gives a horizontal ellipse rooted at the top.
                        ctx.save();
                        const cx = width / 2;
                        const cy = 0;                  // origin at top centre
                        const rx = width * 0.55;       // ellipse half-width
                        const ry = height;             // ellipse half-height
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
