// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// `import QtGraphicalEffects 1.0` resolves to Qt5Compat.GraphicalEffects, with
// the types the corpus uses (ColorOverlay, DropShadow, FastBlur, OpacityMask,
// RadialGradient) and a sample of the rest, and renders.
import QtQuick 2.0
import QtTest 1.0
import QtGraphicalEffects 1.0

Item {
    id: root
    width: 40; height: 40

    Rectangle { id: src; width: 40; height: 40; color: "red"; visible: false }
    ColorOverlay { id: overlay; anchors.fill: src; source: src; color: "#0000ff" }
    DropShadow { source: src; radius: 4; samples: 9; horizontalOffset: 1; visible: false }
    FastBlur { source: src; radius: 8; visible: false }
    OpacityMask { source: src; maskSource: src; visible: false }
    RadialGradient { width: 10; height: 10; visible: false
        gradient: Gradient { GradientStop { position: 0; color: "white" } GradientStop { position: 1; color: "black" } } }
    LinearGradient { width: 10; height: 10; visible: false }
    Desaturate { source: src; visible: false }
    Glow { source: src; visible: false }
    GaussianBlur { source: src; visible: false }

    TestCase {
        name: "QtGraphicalEffects"
        when: windowShown

        function test_types() {
            compare(overlay.color, "#0000ff")
            compare(overlay.source, src)
        }
        function test_renders() {
            // The software scene graph (offscreen without GL) has no shader
            // effects, so the effects draw nothing there.
            if (GraphicsInfo.api === GraphicsInfo.Software)
                skip("software scene graph: shader effects are not rendered")
            var img = grabImage(root)
            var c = img.pixel(20, 20)
            // The overlay paints the opaque source blue.
            verify(Qt.colorEqual(c, "#0000ff"), "pixel " + c)
        }
    }
}
