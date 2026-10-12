pragma ComponentBehavior: Bound

import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Now Bar: live-activity row (music / call / nav / timer) drawn as a
// Sailfish list item: glass-ring glyph, title and a secondary line.
Item {
    id: root

    implicitHeight: Math.max(Silica.Theme.itemSizeSmall, textColumn.implicitHeight + Silica.Theme.paddingSmall * 2)

    property string variant: "music"          // "music" | "call" | "nav" | "timer"
    property string iconName: "music"
    property string label: ""
    property string sublabel: ""
    property color tintColor: Silica.Theme.highlightColor

    property bool playing: variant === "music"
    property bool pulsing: variant === "call"

    readonly property bool down: area.pressed && area.containsMouse

    signal activated

    Rectangle {
        anchors.fill: parent
        color: root.down ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: Silica.Theme.paddingSmall
        anchors.rightMargin: Silica.Theme.paddingSmall
        spacing: Silica.Theme.paddingMedium

        Item {
            id: badgeWrap
            width: Silica.Theme.iconSizeMedium
            height: width
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

                GlyphIcon {
                    anchors.centerIn: parent
                    name: root.iconName
                    size: Silica.Theme.iconSizeExtraSmall
                    color: root.tintColor
                }
            }

            // Call pulse; gated on visible (C8).
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                border.color: Silica.Theme.highlightColor
                opacity: 0.5
                visible: root.pulsing

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.pulsing && root.visible && !MMotion.reduceMotion
                    NumberAnimation {
                        from: 0.5
                        to: 0.0
                        duration: 1200
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        from: 0.0
                        to: 0.5
                        duration: 0
                    }
                }
            }
        }

        Column {
            id: textColumn
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - badgeWrap.width - visualWrap.width - parent.spacing * 2

            Silica.Label {
                width: parent.width
                text: root.label
                color: root.down ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                truncationMode: Silica.TruncationMode.Fade
            }
            Silica.Label {
                width: parent.width
                text: root.sublabel
                color: root.down ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                truncationMode: Silica.TruncationMode.Fade
                visible: text.length > 0
            }
        }

        Item {
            id: visualWrap
            anchors.verticalCenter: parent.verticalCenter
            width: root.variant === "music" ? visualiser.implicitWidth : 0
            height: Silica.Theme.paddingLarge

            Row {
                id: visualiser
                readonly property real unit: Math.max(2, Math.round(Silica.Theme.paddingSmall / 3))
                anchors.verticalCenter: parent.verticalCenter
                spacing: visualiser.unit
                visible: root.variant === "music"

                Repeater {
                    model: [0.5, 0.85, 0.35, 0.7, 0.45]
                    delegate: Rectangle {
                        id: bar
                        required property int index
                        required property real modelData
                        readonly property real fullHeight: Math.round(bar.modelData * visualWrap.height)
                        width: visualiser.unit
                        height: bar.fullHeight
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.tintColor
                        opacity: bar.index % 2 ? 1.0 : 0.5

                        SequentialAnimation on height {
                            loops: Animation.Infinite
                            running: root.playing && root.visible && !MMotion.reduceMotion
                            NumberAnimation {
                                from: bar.fullHeight
                                to: visualiser.unit
                                duration: 280 + bar.index * 70
                                easing.type: Easing.InOutQuad
                            }
                            NumberAnimation {
                                from: visualiser.unit
                                to: bar.fullHeight
                                duration: 280 + bar.index * 70
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: root.activated()
    }
}
