// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

import QtQuick
import MarathonApp.Camera

// The viewfinder, as Qt 5's VideoOutput: shows `source`'s frames turned
// upright, mirrored for a front camera as a mirror would show the person.
Item {
    id: root

    property Camera source
    readonly property alias videoSink: output.videoSink
    readonly property int _rotation: source ? source.orientation : 0

    transform: Scale {
        origin.x: root.width / 2
        xScale: root.source && root.source.position === Camera.FrontFace ? -1 : 1
    }

    onSourceChanged: {
        if (source)
            source.controller.videoSink = videoSink;
    }

    SoftwareVideoOutput {
        id: output

        anchors.centerIn: parent
        width: root._rotation % 180 === 0 ? root.width : root.height
        height: root._rotation % 180 === 0 ? root.height : root.width
        rotation: root._rotation
        fillMode: SoftwareVideoOutput.PreserveAspectFit
    }
}
