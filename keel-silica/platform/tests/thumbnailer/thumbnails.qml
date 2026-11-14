// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
import QtQuick 2.0
import Nemo.Thumbnailer 1.0

Rectangle {
    id: root
    required property url landscape
    required property url rotated
    width: 300
    height: 100
    color: "white"

    Thumbnail {
        objectName: "fit"
        width: 100
        height: 100
        sourceSize.width: 100
        sourceSize.height: 100
        fillMode: Thumbnail.PreserveAspectFit
        source: root.landscape
    }
    Thumbnail {
        objectName: "crop"
        x: 100
        width: 100
        height: 100
        sourceSize.width: 100
        sourceSize.height: 100
        fillMode: Thumbnail.PreserveAspectCrop
        priority: Thumbnail.HighPriority
        source: root.landscape
    }
    Thumbnail {
        objectName: "rotatedFit"
        x: 200
        width: 100
        height: 100
        sourceSize.width: 100
        sourceSize.height: 100
        fillMode: Thumbnail.PreserveAspectFit
        source: root.rotated
    }
}
