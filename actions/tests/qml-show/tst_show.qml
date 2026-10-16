// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// app.show in an app D-Bus activation started (headless): the call for a page
// waits until the page's KeelPage has loaded, then the hidden window is shown,
// the page opened and the app is no longer headless (it stops quitting when
// idle). Run with KEEL_ACTIONS_HEADLESS=1 and the golden manifest, which
// declares the pages before the QML does.
import QtQuick 2.15
import QtQuick.Window 2.15
import QtTest 1.0
import Keel.Actions 1.0
import "../app"

TestCase {
    name: "ShowHeadless"
    when: windowShown

    // The app's window, which a headless launch loads and does not show.
    // Top-level, as the app's view is (Qt makes a Window declared in an item a
    // transient child of that item's window otherwise).
    Window { id: appWindow; visible: false; width: 100; height: 100; transientParent: null }

    Loader { id: declarations; active: false; sourceComponent: NotesActions { } }

    function test_show_waits_for_the_page_then_shows_the_window() {
        verify(KeelActions.headless)
        verify(!appWindow.visible)
        const call = KeelActions.invoke("app.show", { page: "settings" })
        verify(!call.finished)
        declarations.active = true
        tryCompare(call, "finished", true, 2000)
        compare(call.errorCode, "")
        compare(declarations.item.shownPages, ["settings"])
        verify(appWindow.visible)
        verify(!KeelActions.headless)
    }
}
