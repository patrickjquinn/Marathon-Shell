// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PageStack semantics from the Silica PageStack documentation.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private

Item {
    width: 540
    height: 960
    // As in an app's main.qml, where the ApplicationWindow is the root and
    // pages see it through the context.
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    Component { id: pageComponent; Page { property string label } }

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { objectName: "first"; property string label: "first" } }
    }

TestCase {
    id: testCase
    name: "PageStack"
    when: windowShown

    property var statusLog: []

    function logStatus(page) {
        page.statusChanged.connect(function() { statusLog.push(page.objectName + ":" + page.status) })
    }

    function init() {
        // These tests check transitions: keep them on the offscreen platform.
        Private.Config._keelImmediatePageTransitions = false
        // Back to just the initial page.
        while (win.pageStack.depth > 1)
            win.pageStack.pop(undefined, PageStackAction.Immediate)
        // (Silica's popAttached() throws when there is no attached page.)
        if (win.pageStack.nextPage() !== null)
            win.pageStack.popAttached(undefined, PageStackAction.Immediate)
        statusLog = []
    }

    function test_initialPage() {
        compare(win.pageStack.depth, 1)
        verify(win.pageStack.currentPage !== null)
        compare(win.pageStack.currentPage.label, "first")
        compare(win.pageStack.currentPage.status, PageStatus.Active)
        compare(win.pageStack.currentPage.pageContainer, win.pageStack)
        verify(!win.pageStack.busy)
    }

    // Keel: on headless platforms (offscreen, minimal) an animated push or
    // pop completes at once, so app harnesses that poll for the new page see
    // it settled (Private.Config._keelImmediatePageTransitions).
    function test_headlessTransitionsComplete() {
        Private.Config._keelImmediatePageTransitions = true
        var p = win.pageStack.push(pageComponent, { label: "headless", objectName: "headless" })
        verify(!win.pageStack.busy)
        compare(win.pageStack.currentPage, p)
        compare(p.status, PageStatus.Active)
        win.pageStack.pop()
        verify(!win.pageStack.busy)
        compare(win.pageStack.depth, 1)
        Private.Config._keelImmediatePageTransitions = false
        win.pageStack.push(pageComponent, { label: "animated", objectName: "animated" })
        verify(win.pageStack.busy)
        tryCompare(win.pageStack, "busy", false)
    }

    function test_push_pop_immediate() {
        var first = win.pageStack.currentPage
        var p = win.pageStack.push(pageComponent, { label: "second", objectName: "second" }, PageStackAction.Immediate)
        verify(p !== null)
        compare(p.label, "second")
        compare(win.pageStack.depth, 2)
        compare(win.pageStack.currentPage, p)
        compare(p.status, PageStatus.Active)
        compare(first.status, PageStatus.Inactive)
        compare(win.pageStack.previousPage(), first)
        compare(win.pageStack.nextPage(first), p)
        var popped = win.pageStack.pop(undefined, PageStackAction.Immediate)
        compare(popped, p)
        compare(win.pageStack.depth, 1)
        compare(win.pageStack.currentPage, first)
        compare(first.status, PageStatus.Active)
        // The only page is never popped.
        compare(win.pageStack.pop(), null)
        compare(win.pageStack.depth, 1)
    }

    function test_status_sequence() {
        var p = pageComponent.createObject(null, { objectName: "tracked" })
        logStatus(p)
        var first = win.pageStack.currentPage
        logStatus(first)
        win.pageStack.push(p, {}, PageStackAction.Immediate)
        // Silica activates the new page before it deactivates the old one.
        compare(statusLog, ["tracked:1", "tracked:2", "first:3", "first:0"])
        statusLog = []
        win.pageStack.pop(undefined, PageStackAction.Immediate)
        compare(statusLog, ["first:1", "first:2", "tracked:3", "tracked:0"])
        // An Item page pushed by the app is not destroyed when popped.
        verify(p !== null)
        compare(p.visible, false)
        p.destroy()
    }

    function test_animated_push() {
        var p = win.pageStack.push(pageComponent, { label: "anim" })
        verify(win.pageStack.busy)
        compare(p.status, PageStatus.Activating)
        tryCompare(win.pageStack, "busy", false)
        compare(p.status, PageStatus.Active)
        win.pageStack.pop()
        verify(win.pageStack.busy)
        win.pageStack.completeAnimation()
        verify(!win.pageStack.busy)
        compare(win.pageStack.depth, 1)
    }

    function test_push_url_and_context() {
        var p = win.pageStack.push(Qt.resolvedUrl("pages/UrlPage.qml"), { label: "fromUrl" }, PageStackAction.Immediate)
        compare(p.objectName, "urlPage")
        compare(p.label, "fromUrl")
        compare(p.stackDepthSeen, 2)
        // Relative URLs resolve against the pushing page's file.
        var nested = p.pushRelative()
        compare(nested.objectName, "nestedPage")
        win.pageStack.completeAnimation()
        compare(win.pageStack.depth, 3)
    }

    function test_push_array() {
        var top = win.pageStack.push([pageComponent, { page: pageComponent, properties: { label: "last" } }],
                                     undefined, PageStackAction.Immediate)
        compare(win.pageStack.depth, 3)
        compare(top.label, "last")
    }

    function test_pop_to_page() {
        var first = win.pageStack.currentPage
        var a = win.pageStack.push(pageComponent, { label: "a" }, PageStackAction.Immediate)
        win.pageStack.push(pageComponent, { label: "b" }, PageStackAction.Immediate)
        win.pageStack.push(pageComponent, { label: "c" }, PageStackAction.Immediate)
        compare(win.pageStack.depth, 4)
        win.pageStack.pop(a, PageStackAction.Immediate)
        compare(win.pageStack.depth, 2)
        compare(win.pageStack.currentPage, a)
        compare(win.pageStack.find(function(pg) { return pg.label === "first" }), first)
        compare(win.pageStack.find(function(pg) { return pg.label === "zzz" }), null)
    }

    function test_replace() {
        win.pageStack.push(pageComponent, { label: "a" }, PageStackAction.Immediate)
        var r = win.pageStack.replace(pageComponent, { label: "r" }, PageStackAction.Immediate)
        compare(win.pageStack.depth, 2)
        compare(win.pageStack.currentPage, r)
        compare(r.label, "r")
    }

    function test_replaceAbove() {
        var first = win.pageStack.currentPage
        win.pageStack.push(pageComponent, { label: "a" }, PageStackAction.Immediate)
        win.pageStack.push(pageComponent, { label: "b" }, PageStackAction.Immediate)
        var r = win.pageStack.replaceAbove(first, pageComponent, { label: "r" }, PageStackAction.Immediate)
        compare(win.pageStack.depth, 2)
        compare(win.pageStack.previousPage(r), first)
        var all = win.pageStack.replaceAbove(null, pageComponent, { label: "only" }, PageStackAction.Immediate)
        compare(win.pageStack.depth, 1)
        compare(win.pageStack.currentPage, all)
        // Restore a "first" page for the other tests.
        win.pageStack.replaceAbove(null, pageComponent, { label: "first", objectName: "first" }, PageStackAction.Immediate)
    }

    function test_attached_pages() {
        var owner = win.pageStack.currentPage
        verify(!owner.forwardNavigation)
        var att = win.pageStack.pushAttached(pageComponent, { label: "att" })
        verify(att !== null)
        // Attached, not shown: depth and current page unchanged.
        compare(win.pageStack.depth, 1)
        compare(win.pageStack.currentPage, owner)
        compare(att.status, PageStatus.Inactive)
        verify(owner.forwardNavigation)
        compare(win.pageStack.nextPage(owner), att)
        // Navigate forward into it.
        win.pageStack.navigateForward(PageStackAction.Immediate)
        compare(win.pageStack.currentPage, att)
        compare(win.pageStack.depth, 2)
        compare(att.status, PageStatus.Active)
        // Back leaves it attached.
        win.pageStack.navigateBack(PageStackAction.Immediate)
        compare(win.pageStack.currentPage, owner)
        compare(win.pageStack.depth, 1)
        compare(win.pageStack.nextPage(owner), att)
        // Replacing the attached page destroys the old one.
        var att2 = win.pageStack.pushAttached(pageComponent, { label: "att2" })
        compare(win.pageStack.nextPage(owner), att2)
        // popAttached removes it.
        compare(win.pageStack.popAttached(undefined, PageStackAction.Immediate), null)
        compare(win.pageStack.nextPage(owner), null)
        verify(!owner.forwardNavigation)
    }

    function test_pop_from_attached_pops_owner() {
        var first = win.pageStack.currentPage
        var owner = win.pageStack.push(pageComponent, { label: "owner" }, PageStackAction.Immediate)
        win.pageStack.pushAttached(pageComponent, { label: "att" })
        win.pageStack.navigateForward(PageStackAction.Immediate)
        compare(win.pageStack.depth, 3)
        win.pageStack.pop(undefined, PageStackAction.Immediate)
        compare(win.pageStack.depth, 1)
        compare(win.pageStack.currentPage, first)
    }

    function test_back_navigation_flag() {
        var p = win.pageStack.push(pageComponent, { label: "locked" }, PageStackAction.Immediate)
        p.backNavigation = false
        win.pageStack.navigateBack(PageStackAction.Immediate)
        compare(win.pageStack.currentPage, p)
        p.backNavigation = true
        win.pageStack.navigateBack(PageStackAction.Immediate)
        compare(win.pageStack.depth, 1)
    }

    function test_swipe_back() {
        var p = win.pageStack.push(pageComponent, { label: "swipe" }, PageStackAction.Immediate)
        // Drag from left to right across the page.
        mousePress(win, 20, 400)
        for (var x = 40; x <= 400; x += 40)
            mouseMove(win, x, 402, 10)
        mouseRelease(win, 400, 402)
        tryCompare(win.pageStack, "depth", 1)
        tryCompare(win.pageStack, "busy", false)
    }

    // The same with a finger, on a page that scrolls (as on a phone: touch
    // reaches the page's flickable, not mouse events).
    Component {
        id: flickablePage
        Page {
            SilicaFlickable {
                anchors.fill: parent
                contentHeight: 3000
                Column {
                    width: parent.width
                    Repeater { model: 30; Label { text: "row " + index; height: 100 } }
                }
            }
        }
    }

    function test_swipe_back_touch() {
        win.pageStack.push(flickablePage, {}, PageStackAction.Immediate)
        compare(win.pageStack.depth, 2)
        var touch = touchEvent(win)
        touch.press(0, win, 20, 400).commit()
        for (var x = 40; x <= 400; x += 40) {
            touch.move(0, win, x, 402).commit()
            wait(10)
        }
        touch.release(0, win, 400, 402).commit()
        tryCompare(win.pageStack, "depth", 1)
        tryCompare(win.pageStack, "busy", false)
    }

    function test_clear() {
        win.pageStack.push(pageComponent, { label: "x" }, PageStackAction.Immediate)
        win.pageStack.clear()
        compare(win.pageStack.depth, 0)
        compare(win.pageStack.currentPage, null)
        win.pageStack.push(pageComponent, { label: "first", objectName: "first" }, PageStackAction.Immediate)
    }

    function test_orientation() {
        var p = win.pageStack.currentPage
        compare(win.orientation, Orientation.Portrait)
        compare(p.orientation, Orientation.Portrait)
        verify(p.isPortrait)
        // The page allows portrait only (default): device landscape is ignored.
        win.deviceOrientation = Orientation.Landscape
        // Orientation is chosen synchronously; no transition starts.
        compare(win.pageStack._ongoingTransitionCount, 0)
        compare(win.orientation, Orientation.Portrait)
        // Pages change orientation through their orientation transition.
        p.allowedOrientations = Orientation.All
        tryCompare(win, "orientation", Orientation.Landscape)
        tryCompare(p, "orientation", Orientation.Landscape)
        verify(p.isLandscape)
        compare(win.screenRotation, 90)
        tryCompare(p, "width", win.height)
        // Window mask restricts further; falls back in the documented order.
        win.allowedOrientations = Orientation.PortraitInverted | Orientation.LandscapeInverted
        tryCompare(win, "orientation", Orientation.LandscapeInverted)
        win.allowedOrientations = Orientation.All
        win.deviceOrientation = Orientation.Portrait
        p.allowedOrientations = Orientation.Portrait
        tryCompare(win, "orientation", Orientation.Portrait)
    }

    // PageStack.testSlideTransition() asks the window for the next page's
    // orientation with one argument (the device orientation is the
    // default): in landscape, pushing a page that also allows landscape must
    // slide, not fade.
    function test_landscapePushSlides() {
        var first = win.pageStack.currentPage
        first.allowedOrientations = Orientation.All
        win.deviceOrientation = Orientation.Landscape
        tryCompare(first, "orientation", Orientation.Landscape)
        tryCompare(win.pageStack, "busy", false)
        compare(win._selectOrientation(Orientation.All), Orientation.Landscape)
        var p = win.pageStack.push(pageComponent, { objectName: "landscape", allowedOrientations: Orientation.All })
        var container = p.__stack_container
        verify(container)
        // Slide: the new page starts off to the side at full opacity. A fade
        // starts in place (dragOffset 0) at opacity 0.
        verify(container.dragOffset !== 0)
        compare(container.opacity, 1.0)
        tryCompare(win.pageStack, "busy", false)
        compare(p.orientation, Orientation.Landscape)
        // A page that only allows portrait fades in (orientation changes).
        var q = win.pageStack.push(pageComponent, { objectName: "portrait" })
        compare(q.__stack_container.dragOffset, 0)
        compare(q.__stack_container.opacity, 0)
        tryCompare(win.pageStack, "busy", false)
        while (win.pageStack.depth > 1)
            win.pageStack.pop(undefined, PageStackAction.Immediate)
        win.deviceOrientation = Orientation.Portrait
        first.allowedOrientations = Orientation.Portrait
        tryCompare(win, "orientation", Orientation.Portrait)
    }
}
}
