// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// A wrapping Label with TruncationMode.Fade and room for two lines (Pilot's
// suggestion tiles) elides its last line instead of fading. Its binding
// loop on _elideText (eliding changed lineCount, which the binding read) is
// guarded by Pilot's smoke test, which fails on any QML warning: it showed
// 16 loops before the fix and none after. This file does not reproduce the
// loop itself (it needs Pilot's tile in its row); it checks the behaviour
// and that nothing here loops.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    id: root
    width: 540
    height: 400

    TestCase {
        name: "LabelWrapFade"
        when: windowShown

        function test_wrapping_fade_elides_without_a_loop() {
            failOnWarning(/Binding loop/)
            var box = Qt.createQmlObject(
                "import QtQuick 2.6; import Sailfish.Silica 1.0\n"
                + "Item { width: 0; height: 200\n"
                + "  property alias label: label\n"
                + "  Label { id: label; x: 24; width: parent.width - 48\n"
                + "    anchors.bottom: parent.bottom\n"
                + "    text: 'A suggestion long enough to wrap over more than the two lines it is given room for'\n"
                + "    wrapMode: Text.Wrap; maximumLineCount: 2; truncationMode: TruncationMode.Fade } }",
                root)
            // Laid out at no width first, as a tile before its row is sized.
            wait(50)
            box.width = 260
            wait(0)
            box.label.text = box.label.text + " and then some more"
            box.width = 300
            wait(0)
            compare(box.label.lineCount, 2)
            verify(box.label._elideText, "elides its last line")
            verify(!box.label._fadeText)
            box.destroy()
        }

        function test_single_line_fade_is_unchanged() {
            failOnWarning(/Binding loop/)
            var l = Qt.createQmlObject(
                "import QtQuick 2.6; import Sailfish.Silica 1.0\n"
                + "Label { width: 200; text: 'A single line far too long for its width'; truncationMode: TruncationMode.Fade }",
                root)
            wait(0)
            // On a GPU it fades; on the software scene graph it elides.
            verify(l._fadeText || l._elideText)
            compare(l.lineCount, 1)
            l.destroy()
        }
    }
}
