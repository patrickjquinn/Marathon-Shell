// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0
import MarathonApp.Camera 1.0

Item {
    id: slider

    property int alignment: Qt.AlignRight
    property int valueCount_: Settings.global.exposureCompensationValues.length
    property real divisionSize_: (height - handle.height) / (valueCount_ - 1)
    property int value: Settings.global.exposureCompensation
    property color highlightColor: Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)

    onValueChanged: {
        if (!mouseArea.drag.active) {
            updateHandlePosition();
        }
    }

    Component.onCompleted: updateHandlePosition()

    function updateHandlePosition() {
        var index = Settings.global.exposureCompensationValues.indexOf(value);
        handle.y = index * divisionSize_ + mouseArea.drag.minimumY;
    }

    width: Theme.itemSizeMedium

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 2
        y: handle.height / 2
        height: parent.height - handle.height
        Rectangle {
            anchors.centerIn: parent
            height: 2
            width: Theme.paddingLarge
        }
    }

    Rectangle {
        id: handle

        color: "black"
        width: icon.width * 0.8
        height: icon.height * 0.8
        radius: Theme.paddingSmall / 2
        anchors.horizontalCenter: parent.horizontalCenter

        Behavior on y {
            id: handleBehavior

            enabled: false
            NumberAnimation {
                id: handleAnimation

                duration: 200
                easing.type: Easing.InOutQuad
            }
        }

        onYChanged: {
            if (mouseArea.drag.active) {
                var index = Math.round((y - mouseArea.drag.minimumY) / (mouseArea.drag.maximumY - mouseArea.drag.minimumY) * (valueCount_ - 1));
                if (index >= 0) {
                    Settings.global.exposureCompensation = Settings.global.exposureCompensationValues[index];
                }
            }
        }

        MouseArea {
            id: mouseArea

            width: Theme.itemSizeMedium
            height: Theme.itemSizeMedium
            anchors.centerIn: icon

            drag {
                target: handle
                axis: Drag.YAxis
                minimumY: 0
                maximumY: slider.height - handle.height
                threshold: Theme.startDragDistance / 2

                onActiveChanged: {
                    handleBehavior.enabled = !drag.active;
                    if (!drag.active) {
                        updateHandlePosition();
                    }
                }
            }

            onReleased: releaseTimer.restart()
            Timer {
                id: releaseTimer
                interval: 2000
            }
        }
        Image {
            id: icon

            anchors.centerIn: parent
            source: "image://theme/icon-camera-exposure-compensation" + (mouseArea.pressed ? "?" + highlightColor : "")
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        x: alignment === Qt.AlignLeft ? parent.width + Theme.paddingSmall : -width - Theme.paddingSmall
        height: parent.height
        Repeater {
            model: Settings.global.exposureCompensationValues
            delegate: Item {
                property bool selected: Settings.global.exposureCompensation == modelData
                height: divisionSize_
                width: Theme.itemSizeSmall
                opacity: (mouseArea.pressed || handleAnimation.running || releaseTimer.running) && selected ? 1.0 : 0.0
                Behavior on opacity {
                    FadeAnimation {}
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    x: alignment === Qt.AlignLeft ? 0 : parent.width - width
                    color: highlightColor
                    text: Settings.exposureText(modelData)
                    font.bold: true
                }
            }
        }
    }
}
