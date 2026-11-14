// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Gallery: ThumbnailImage (a pressable, selectable square photo
// thumbnail; a video placeholder for videos) and ImageViewer (fitted photo,
// zoom by double tap, tap signal).
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Gallery 1.0

Item {
    id: root
    width: 540
    height: 960

    // A red 40x20 PNG, inline (no binary files in the tree).
    property url photo: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAI0lEQVR42u3NsQ0AAAjAoP7/tJ7hIAk7TZ1ILBaLxWKx+E+8ffodDqIehz0AAAAASUVORK5CYII="
    property int clicks: 0

    ThumbnailImage {
        id: thumb
        source: root.photo
        size: 120
        onClicked: root.clicks++
    }

    ThumbnailImage {
        id: video
        x: 200
        source: "file:///nonexistent/clip.mp4"
        size: 100
        mimeType: "video/mp4"
        duration: 75
    }

    ImageViewer {
        id: viewer
        y: 300
        width: 540
        height: 400
        source: root.photo
        active: true
    }

    SignalSpy { id: viewerClicks; target: viewer; signalName: "clicked" }

    TestCase {
        name: "Gallery"
        when: windowShown

        function test_thumbnailImage() {
            compare(thumb.width, 120)
            compare(thumb.height, 120)
            tryCompare(thumb, "status", Image.Ready)
            verify(!thumb.isVideo)
            var img = grabImage(thumb)
            verify(Qt.colorEqual(img.pixel(60, 60), "red"))
            mouseClick(thumb)
            compare(root.clicks, 1)
            verify(!thumb.highlighted)
            thumb.selected = true
            verify(thumb.highlighted)
            thumb.selected = false
        }

        function test_videoThumbnail() {
            verify(video.isVideo)
            compare(video.width, 100)
        }

        function test_imageViewer() {
            tryCompare(viewer, "status", Image.Ready)
            verify(!viewer.zoomed)
            verify(!viewer.error)
            mouseDoubleClickSequence(viewer, 270, 200)
            tryVerify(function() { return viewer.zoomed })
            viewer.zoomOut()
            tryVerify(function() { return !viewer.zoomed })
            wait(400)
            var before = viewerClicks.count
            mouseClick(viewer, 100, 100)
            tryCompare(viewerClicks, "count", before + 1)
        }
    }
}
