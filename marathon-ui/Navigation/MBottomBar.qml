import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonOS.Shell

Rectangle {
    id: root

    property var actions: []

    signal actionClicked(int index)

    // ── Shrink-on-scroll · iOS 26 / M3 Expressive chrome ───────────
    // Same contract as MTopBar.scrollSource — bind to a Flickable to
    // make the bar shrink on downward scroll and expand on upward
    // scroll. Default unbound = fixed-height legacy behaviour.
    property var scrollSource: null
    property bool minimized: false
    property real _lastContentY: 0

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real barHeight: Math.round(72 * scaleFactor)
    readonly property real barHeightMin: Math.round(48 * scaleFactor)
    width: parent ? parent.width : Math.round(400 * scaleFactor)
    height: minimized ? barHeightMin : barHeight
    color: MColors.bb10Elevated
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    Behavior on height {
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

    Row {
        anchors.centerIn: parent
        spacing: MSpacing.md

        Repeater {
            model: root.actions

            MButton {
                text: modelData.text || ""
                iconName: modelData.icon || ""
                variant: modelData.variant || "default"
                onClicked: root.actionClicked(index)
            }
        }
    }
}
