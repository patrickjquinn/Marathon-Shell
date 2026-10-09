// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Dialog semantics from the Silica Dialog documentation.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0 as Private

Item {
    width: 540
    height: 960
    // As in an app's main.qml, where the ApplicationWindow is the root.
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { objectName: "first" } }
    }

    Component {
        id: dialogComponent
        Dialog {
            id: dlg
            property var log: []
            property string name
            DialogHeader { id: header; objectName: "header"; title: "Title" }
            TextField { id: field; y: header.height; text: "Ada" }
            onOpened: log.push("opened")
            onDone: {
                log.push("done:" + result)
                if (result === DialogResult.Accepted)
                    name = field.text
            }
            onAccepted: log.push("accepted")
            onRejected: log.push("rejected")
            onAcceptBlocked: log.push("blocked")
        }
    }
    Component { id: pageComponent; Page { property string label } }

    TestCase {
        name: "Dialog"
        when: windowShown

        function init() {
            // These tests check transitions: keep them on the offscreen platform.
            Private.Config._keelImmediatePageTransitions = false
            win.pageStack.completeAnimation()
            tryCompare(win.pageStack, "busy", false)
            while (win.pageStack.depth > 1)
                win.pageStack.pop(undefined, PageStackAction.Immediate)
        }

        function open() {
            // A push is refused while a transition runs (Silica's PageStack).
            tryCompare(win.pageStack, "busy", false)
            var d = win.pageStack.push(dialogComponent, {}, PageStackAction.Immediate)
            compare(d.status, DialogStatus.Opened)
            return d
        }

        function test_open_and_accept() {
            var d = open()
            compare(d.log, ["opened"])
            compare(d.result, DialogResult.None)
            d.accept()
            compare(d.log, ["opened", "done:1", "accepted"])
            compare(d.result, DialogResult.Accepted)
            compare(d.name, "Ada")
            tryCompare(win.pageStack, "depth", 1)
        }

        function test_reject() {
            var d = open()
            d.reject()
            compare(d.log, ["opened", "done:2", "rejected"])
            compare(d.result, DialogResult.Rejected)
            tryCompare(win.pageStack, "depth", 1)
        }

        function test_close() {
            var d = open()
            d.close()
            compare(d.log, ["opened", "done:0"])
            compare(d.result, DialogResult.None)
            tryCompare(win.pageStack, "depth", 1)
        }

        function test_canAccept() {
            var d = open()
            d.canAccept = false
            d.accept()
            compare(d.log, ["opened", "blocked"])
            compare(win.pageStack.depth, 2)
            // Forward navigation is the accept gesture.
            win.pageStack.navigateForward()
            compare(d.log, ["opened", "blocked", "blocked"])
            d.canAccept = true
            win.pageStack.navigateForward()
            compare(d.log, ["opened", "blocked", "blocked", "done:1", "accepted"])
            tryCompare(win.pageStack, "depth", 1)
        }

        function test_navigate_back_rejects() {
            var d = open()
            win.pageStack.navigateBack()
            compare(d.result, DialogResult.Rejected)
            tryCompare(win.pageStack, "depth", 1)
        }

        function test_dialog_open_method() {
            var d = dialogComponent.createObject(null)
            d.open(false, true)
            compare(win.pageStack.currentPage, d)
            compare(d.log, ["opened"])
            d.reject()
            tryCompare(win.pageStack, "depth", 1)
            tryCompare(win.pageStack, "busy", false)
            d.destroy()
        }

        function test_header_taps() {
            var d = open()
            var header = findChild(d, "header")
            verify(header)
            compare(header.dialog, d)
            compare(header.acceptText, header.defaultAcceptText)
            mouseClick(header, header.width - 20, header.height / 2)
            compare(d.result, DialogResult.Accepted)
            tryCompare(win.pageStack, "depth", 1)
            d = open()
            header = findChild(d, "header")
            mouseClick(header, 20, Theme.itemSizeLarge / 2)
            compare(d.result, DialogResult.Rejected)
            tryCompare(win.pageStack, "depth", 1)
        }

        function test_acceptDestination_push() {
            var d = win.pageStack.push(dialogComponent, { acceptDestination: pageComponent,
                                                         acceptDestinationProperties: { label: "dest" } },
                                       PageStackAction.Immediate)
            verify(d.acceptDestinationInstance !== null)
            compare(d.acceptDestinationInstance.label, "dest")
            d.accept()
            tryCompare(win.pageStack, "busy", false)
            compare(win.pageStack.currentPage.label, "dest")
            compare(d.result, DialogResult.Accepted)
            // Back from the destination returns to the dialog (reactivated,
            // result reset), as in Silica.
            win.pageStack.navigateBack(PageStackAction.Immediate)
            compare(win.pageStack.currentPage, d)
            compare(d.result, DialogResult.None)
        }

        function test_acceptDestination_replace() {
            var first = win.pageStack.currentPage
            var mid = win.pageStack.push(pageComponent, { label: "mid" }, PageStackAction.Immediate)
            var d = win.pageStack.push(dialogComponent, { acceptDestination: pageComponent,
                                                         acceptDestinationProperties: { label: "dest" },
                                                         acceptDestinationAction: PageStackAction.Replace },
                                       PageStackAction.Immediate)
            d.accept()
            win.pageStack.completeAnimation()
            // The dialog is replaced by the destination (Silica's PageStack).
            compare(win.pageStack.depth, 3)
            compare(win.pageStack.currentPage.label, "dest")
            compare(win.pageStack.previousPage(), mid)
        }

        function test_acceptDestination_pop() {
            var first = win.pageStack.currentPage
            win.pageStack.push(pageComponent, { label: "mid" }, PageStackAction.Immediate)
            var d = win.pageStack.push(dialogComponent, { acceptDestination: first,
                                                         acceptDestinationAction: PageStackAction.Pop },
                                       PageStackAction.Immediate)
            d.accept()
            win.pageStack.completeAnimation()
            compare(win.pageStack.depth, 1)
            compare(win.pageStack.currentPage, first)
        }
    }
}
