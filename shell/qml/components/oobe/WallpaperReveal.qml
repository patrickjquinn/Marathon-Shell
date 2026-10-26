pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects

// A wallpaper that opens in a circle from a point; a cross-fade under
// reduce motion.
Item {
    id: root

    property url current: SettingsManagerCpp.wallpaperPath
    property url target
    property real centerX: width / 2
    property real centerY: height / 2
    property real progress: 0
    property bool pending: false
    readonly property bool revealing: pending || anim.running
    readonly property int duration: SettingsManagerCpp.reduceMotion ? 200 : 450
    readonly property real maxRadius: Math.hypot(Math.max(centerX, width - centerX), Math.max(centerY, height - centerY))

    function reveal(url, x, y) {
        anim.stop();
        if (revealing)
            finish();
        current = current;
        target = url;
        centerX = x;
        centerY = y;
        progress = 0;
        pending = true;
        start();
    }

    function start() {
        if (!pending || incoming.status === Image.Loading)
            return;
        pending = false;
        if (incoming.status === Image.Ready)
            anim.restart();
        else
            finish();
    }

    function finish() {
        current = target;
        progress = 0;
        pending = false;
    }

    Image {
        anchors.fill: parent
        source: root.current
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectCrop
    }

    Image {
        id: incoming

        anchors.fill: parent
        visible: false
        source: root.target
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: root.start()
    }

    Item {
        id: circle

        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            x: root.centerX - width / 2
            y: root.centerY - height / 2
            width: 2 * root.progress * root.maxRadius
            height: width
            radius: width / 2
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: incoming
        visible: anim.running
        maskEnabled: !SettingsManagerCpp.reduceMotion
        maskSource: circle
        opacity: SettingsManagerCpp.reduceMotion ? root.progress : 1
    }

    NumberAnimation {
        id: anim

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.duration
        easing.type: Easing.OutCubic
        onFinished: root.finish()
    }
}
