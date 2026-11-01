// SPDX-FileCopyrightText: 2021 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.6
import Sailfish.Silica 1.0

// The lens switch redrawn so the lens in use is plain at a
// glance. The Jolla Camera drew two equal outlined circles and only tinted
// the selected one; here both sit on one translucent pill, the lens in use
// is larger, filled and reads as a multiplier ("1×", with the digital zoom
// on top: "1.6×"), and the others are smaller and quieter ("0.5").
Item {
    id: root

    property string currentDeviceId
    property var labels: []
    property alias model: repeater.model
    property int orientation: Qt.Vertical
    // The digital zoom on the lens in use.
    property real zoom: 1.0
    property color highlightColor: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)

    signal selected(string deviceId)
    // The lens in use was tapped while zoomed in: back to its own 1×.
    signal zoomReset

    readonly property real _big: Theme.itemSizeExtraSmall
    readonly property real _small: Math.round(Theme.itemSizeExtraSmall * 0.72)
    readonly property real _pad: Theme.paddingSmall

    // From the model, not repeater.count, which lags behind the
    // items the repeater makes (Qt 6's Grid warned about more visible items
    // than rows times columns while it caught up).
    readonly property int _count: model && model.length !== undefined ? model.length : 0

    readonly property bool _supportNotEnabled: !!model && model.length > 1 && labels.length === 0
    // Checked once the bindings have settled: the camera list and the labels
    // arrive one after the other at start-up.
    on_SupportNotEnabledChanged: if (_supportNotEnabled)
        Qt.callLater(_warnIfUnlabelled)
    function _warnIfUnlabelled() {
        if (_supportNotEnabled)
            console.warn("Several back cameras but no labels for them: set dconf /apps/shipwright-shoal-camera/backCameraLabels");
    }

    // "1", "0.5", "1.6" ("0,5" in German): a whole number without its
    // decimals, in the locale's decimal separator.
    function _number(value) {
        var rounded = Math.round(value * 10) / 10;
        return rounded.toLocaleString(Qt.locale(), "f", rounded % 1 === 0 ? 0 : 1);
    }

    // "1×", "0.5×", "1.6×"
    function _multiplier(value) {
        return _number(value) + "\u00d7";
    }

    width: grid.width + 2 * _pad
    height: grid.height + 2 * _pad

    // Light, so it reads on the black bar below the picture as well as over
    // the picture itself.
    Rectangle {
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        color: Theme.rgba(Theme.lightPrimaryColor, 0.16)
    }

    Grid {
        id: grid

        anchors.centerIn: parent
        columns: root.orientation === Qt.Vertical ? 1 : Math.max(1, root._count)
        rows: root.orientation === Qt.Vertical ? Math.max(1, root._count) : 1
        spacing: Theme.paddingSmall
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Repeater {
            id: repeater

            SilicaItem {
                id: lens

                readonly property bool current: modelData.deviceId === root.currentDeviceId
                readonly property string label: root.labels.length > model.index ? root.labels[model.index] : ""
                readonly property real _side: current ? root._big : root._small

                highlighted: mouseArea.pressed && mouseArea.containsMouse
                // The pill keeps the larger size's room, so the row does not
                // jump as the lenses swap sizes.
                width: root._big
                height: root._big
                visible: label != ''

                MouseArea {
                    id: mouseArea

                    anchors.fill: parent
                    onClicked: {
                        if (!lens.current)
                            root.selected(modelData.deviceId);
                        else if (root.zoom > 1.01)
                            root.zoomReset();
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: lens._side
                    height: width
                    radius: width / 2
                    color: lens.current ? Theme.rgba(Theme.darkPrimaryColor, 0.55) : "transparent"
                    border {
                        width: lens.current ? Theme._lineWidth : 0
                        color: root.highlightColor
                    }
                    opacity: lens.highlighted ? Theme.opacityHigh : 1.0
                    Behavior on width {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Label {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -Theme.pixelRatio
                    text: lens.current ? root._multiplier(parseFloat(lens.label) * root.zoom) : root._number(parseFloat(lens.label))
                    color: lens.current || lens.highlighted ? root.highlightColor : Theme.lightPrimaryColor
                    font.pixelSize: lens.current ? Theme.fontSizeSmall : Theme.fontSizeExtraSmall
                    font.bold: lens.current
                }
            }
        }
    }
}
