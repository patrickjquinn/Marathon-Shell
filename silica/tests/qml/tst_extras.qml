// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Corpus blockers added in Keel 0.1: StandardPaths, LinkedLabel,
// ButtonLayout, ScrollDecorator, IconTextSwitch, InteractionHintLabel,
// TouchInteractionHint.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0

Item {
    id: root
    width: 540
    height: 960

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: 3000
        contentWidth: 2000
        ScrollDecorator { id: scroll }
    }

    ButtonLayout {
        id: buttons
        width: 540
        Button { id: b1; text: "One" }
        Button { id: b2; text: "Two" }
        Button { id: b3; text: "Three"; ButtonLayout.newLine: true }
        Button { id: b4; text: "Four" }
        Button { id: b5; text: "Five" }
    }

    LinkedLabel {
        id: linked
        width: 500
        plainText: "See https://example.org/a/very/long/path/to/something, mail a.b@example.com or call +358 40 123 4567. <b>not bold</b>"
        property string activated
        defaultLinkActions: false
        onLinkActivated: function(link) { activated = link }
    }

    IconTextSwitch { id: iconSwitch; text: "Location"; icon.source: "image://theme/icon-m-gps" }
    InteractionHintLabel { id: hintLabel; text: "Pull down"; invert: true }
    TouchInteractionHint { id: touchHint; direction: TouchInteraction.Down; interactionMode: TouchInteraction.Pull; loops: 1 }
    TouchInteractionHint { id: loopingHint; direction: TouchInteraction.Right; loops: 3; _testMode: true }
    // As Shoal Camera's hints are made: restarted from Component.onCompleted
    // in an asynchronous Loader, running to the end.
    Loader {
        id: hintLoader
        active: false
        asynchronous: true
        sourceComponent: TouchInteractionHint {
            direction: TouchInteraction.Down
            alwaysRunToEnd: true
            _testMode: true
            Component.onCompleted: restart()
        }
    }

    TestCase {
        name: "Extras"
        when: windowShown

        function test_standardPaths() {
            verify(StandardPaths.home.length > 0)
            verify(StandardPaths.temporary.length > 0)
            verify(StandardPaths.data.length > 0)
            verify(StandardPaths.cache.length > 0)
            verify(StandardPaths.genericData.length > 0)
            verify(StandardPaths.documents !== undefined)
            verify(StandardPaths.download !== undefined)
            verify(StandardPaths.music !== undefined)
            verify(StandardPaths.pictures !== undefined)
            verify(StandardPaths.videos !== undefined)
        }

        function test_linkedLabel() {
            var t = linked.text
            verify(t.indexOf('<a href="https://example.org/a/very/long/path/to/something">') >= 0, t)
            verify(t.indexOf('<a href="mailto:a.b@example.com">') >= 0, t)
            verify(t.indexOf('<a href="tel:+358401234567">') >= 0, t)
            verify(t.indexOf("&lt;b&gt;") >= 0, "plain text is escaped")
            compare(linked.linkColor, Theme.primaryColor)
            linked.shortenUrl = true
            verify(linked.text.indexOf(">example.org/a/very/long/pat…</a>") >= 0, linked.text)
            linked.linkActivated("mailto:a.b@example.com")
            compare(linked.activated, "mailto:a.b@example.com")
        }

        function test_buttonLayout() {
            tryVerify(function() { return buttons.implicitHeight > 0 })
            // Row 1: One, Two. Row 2 (newLine): Three, Four. Row 3: Five.
            compare(b1.y, b2.y)
            verify(b3.y > b1.y)
            compare(b3.y, b4.y)
            verify(b5.y > b4.y)
            // Equal widths within a row, and for adjacent rows of equal size.
            compare(b1.width, b2.width)
            compare(b3.width, b1.width)
            verify(b1.width >= Theme.buttonWidthSmall)
            // Centred.
            fuzzyCompare(b1.x, buttons.width - (b2.x + b2.width), 1)
            fuzzyCompare(b5.x + b5.width / 2, buttons.width / 2, 1)
            // Hiding a button reflows.
            b2.visible = false
            tryVerify(function() { return b3.y === b1.y || b3.y > b1.y })
            b2.visible = true
        }

        function test_scrollDecorator() {
            // As in Silica, ScrollDecorator.flickable stays as set (null);
            // its vertical and horizontal decorators find the flickable and
            // move into it.
            var found = 0
            for (var i = 0; i < flick.children.length; ++i) {
                if (flick.children[i].flickable === flick)
                    ++found
            }
            compare(found, 2)
        }

        function test_iconTextSwitch() {
            compare(iconSwitch.icon.source.toString(), "image://theme/icon-m-gps")
            verify(!iconSwitch.checked)
            mouseClick(iconSwitch, 10, iconSwitch.height / 2)
            verify(iconSwitch.checked)
        }

        function test_hints() {
            verify(hintLabel.height > 0)
            compare(hintLabel.textColor, Theme.highlightColor)
            touchHint.start()
            verify(touchHint.running)
            touchHint.stop()
            verify(!touchHint.running)
            compare(touchHint.opacity, 0)
            compare(TouchInteraction.Pull, 2)
        }

        // The hint's animation group: its first animation (the resume pause)
        // must not change while the group runs. Its duration was bound to
        // _interrupted, which the group's own ScriptActions change; on Qt
        // 6.4 that crashed in QAnimationGroupJob::ungroupChild (Shoal
        // Camera's camera-roll and settings hints).
        function hintGroup(hint) {
            for (var i = 0; i < hint.data.length; ++i) {
                var o = hint.data[i]
                if (o.animations !== undefined && o.animations.length > 3)
                    return o
            }
            return null
        }

        SignalSpy { id: pauseSpy; signalName: "durationChanged" }

        function test_touchHintLoopsWithoutChangingTheRunningGroup() {
            var group = hintGroup(loopingHint)
            verify(group !== null)
            pauseSpy.target = group.animations[0]
            pauseSpy.clear()
            loopingHint.start()
            verify(loopingHint.running)
            tryVerify(function() { return loopingHint._interrupted }, 2000)
            compare(pauseSpy.count, 0)
            // Restarted while running (Shoal Camera does on every capture),
            // and as when the app becomes active again mid-hint.
            loopingHint.restart()
            wait(30)
            loopingHint._restartGroup()
            tryCompare(loopingHint, "running", false, 10000)
            compare(loopingHint._loopsRun, 3)
            // Changed only between runs: 800 ms after the interrupted run.
            verify(pauseSpy.count <= 2)
        }

        function test_touchHintInAsynchronousLoader() {
            hintLoader.active = true
            tryVerify(function() { return hintLoader.item !== null && hintLoader.item.running }, 5000)
            tryCompare(hintLoader.item, "running", false, 10000)
            hintLoader.active = false
        }
    }
}
