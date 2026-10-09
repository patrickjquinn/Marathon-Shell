// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Label's TruncationMode.Fade (Silica public documentation): a one-line text
// wider than the label fades out towards its end through Silica's opacity
// ramp shader when the scene graph runs shaders (OpenGL: run under Xvfb), and
// is elided on the software scene graph, which runs none. Text that fits is
// left alone (also after it grew); right-aligned text fades at its start.
import QtQuick
import QtTest
import Sailfish.Silica 1.0

Rectangle {
    width: 400
    height: 200
    color: "black"

    Label {
        id: longText
        y: 0
        width: 200
        color: "white"
        font.pixelSize: 40
        text: "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
        truncationMode: TruncationMode.Fade
    }
    Label {
        id: rightAligned
        y: 60
        width: 200
        color: "white"
        font.pixelSize: 40
        horizontalAlignment: Text.AlignRight
        text: "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"
        truncationMode: TruncationMode.Fade
    }
    Label {
        id: fits
        y: 120
        width: 200
        color: "white"
        text: "M"
        truncationMode: TruncationMode.Fade
    }

    TestCase {
        name: "LabelFade"
        when: windowShown

        readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software

        // Brightest red value in a column of a grabbed label.
        function brightness(image, x, height) {
            var best = 0
            for (var y = 0; y < height; ++y)
                best = Math.max(best, image.red(x, y))
            return best
        }

        function test_fade() {
            if (!shaders) {
                compare(longText._fadeText, false)
                compare(longText.elide, Text.ElideRight)
                compare(rightAligned.elide, Text.ElideLeft)
                return
            }
            verify(longText._fadeText)
            verify(longText.layer.enabled)
            compare(longText.elide, Text.ElideNone)
            waitForRendering(longText)
            var image = grabImage(longText)
            var start = brightness(image, 5, image.height)
            var end = brightness(image, image.width - 3, image.height)
            verify(start > 200, "start of the text at full strength: " + start)
            verify(end < start / 3, "end faded: " + end + " vs " + start)
        }

        function test_rightAlignedFadesAtStart() {
            if (!shaders)
                skip("software scene graph: elided (test_fade)")
            verify(rightAligned._fadeText)
            waitForRendering(rightAligned)
            var image = grabImage(rightAligned)
            var start = brightness(image, 3, image.height)
            var end = brightness(image, image.width - 5, image.height)
            verify(end > 200, "end at full strength: " + end)
            verify(start < end / 3, "start faded: " + start + " vs " + end)
        }

        function test_fitsUntouched() {
            compare(fits._fadeText, false)
            compare(fits.elide, shaders ? Text.ElideNone : Text.ElideRight)
            verify(!fits.layer.enabled)
        }

        // A label as wide as its text (PageHeader's description: width
        // min(implicitWidth, room)) whose text grows ("1 entry" to "4
        // entries") shows all of it, not the old width's elided end: as
        // Shoal Keys' list header shows its count.
        function test_growingTextWithItsOwnWidth() {
            var view = Qt.createQmlObject("import QtQuick; import Sailfish.Silica 1.0; SilicaListView {"
                + " property int n: 0; width: 400; height: 200; model: 0;"
                + " header: Column { width: 400; PageHeader { objectName: 'ph'; title: 'Personal';"
                + " description: n === 1 ? '1 entry' : n + ' entries' } } }", parent)
            wait(20)
            view.n = 1
            wait(20)
            view.n = 4
            wait(50)
            var header = view.headerItem.children[0]
            var label = header._descriptionLabel
            compare(label.text, "4 entries")
            compare(label.contentWidth, label.implicitWidth)
            view.destroy()
        }
    }
}
