pragma ComponentBehavior: Bound

import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// The tab header: equal-width tabs, current one in highlightColor
// with a thin highlight line beneath; no boxes or glows.
Rectangle {
    id: root

    property int activeTab: 0
    property alias tabs: tabRepeater.model

    signal tabSelected(int index)

    // Bind to a Flickable to shrink on scroll-down, expand on scroll-up.
    property var scrollSource: null
    property bool minimized: false
    property real _lastContentY: 0

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real barHeight: Silica.Theme.itemSizeMedium
    readonly property real barHeightMin: Silica.Theme.itemSizeSmall
    height: minimized ? barHeightMin : barHeight
    color: "transparent"

    Behavior on height {
        NumberAnimation {
            duration: MMotion.moderate
            easing.type: Easing.OutCubic
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

    readonly property real _tabWidth: tabRepeater.count > 0 ? root.width / tabRepeater.count : root.width

    Rectangle {
        id: sharedIndicator
        x: root.activeTab * root._tabWidth + Silica.Theme.paddingMedium
        width: Math.max(0, root._tabWidth - Silica.Theme.paddingMedium * 2)
        anchors.bottom: parent.bottom
        height: Math.max(1, Math.round(Silica.Theme.paddingSmall / 3))
        color: Silica.Theme.highlightColor
        visible: tabRepeater.count > 0

        Behavior on x {
            NumberAnimation {
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
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

                required property var modelData
                required property int index

                width: root.width / tabRepeater.count
                height: parent.height

                property bool selected: index === root.activeTab
                readonly property bool down: tabMouseArea.pressed && tabMouseArea.containsMouse
                readonly property color tint: (selected || down) ? Silica.Theme.highlightColor : Silica.Theme.primaryColor

                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.label || ""
                Accessible.selected: selected
                Accessible.onPressAction: {
                    root.activeTab = index;
                    root.tabSelected(index);
                }

                Column {
                    anchors.centerIn: parent
                    spacing: Silica.Theme.paddingSmall

                    GlyphIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: tabButton.modelData.icon || ""
                        size: Silica.Theme.iconSizeSmall
                        color: tabButton.tint
                        visible: name.length > 0
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tabButton.modelData.label || ""
                        color: tabButton.tint
                        font.family: Silica.Theme.fontFamily
                        font.pixelSize: Silica.Theme.fontSizeMedium
                        visible: text.length > 0
                    }
                }

                MouseArea {
                    id: tabMouseArea
                    anchors.fill: parent
                    onPressed: MHaptics.lightImpact()
                    onClicked: {
                        Qt.inputMethod.hide(); // qmllint disable missing-property
                        root.activeTab = tabButton.index;
                        root.tabSelected(tabButton.index);
                    }
                }
            }
        }
    }
}
