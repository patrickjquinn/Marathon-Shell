// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Console capture costs every page a wrapped console and a message per call,
// so it is there only while captureConsole is on; reports a page script must
// send (Pacific's autoconsent) go to their own handler in the page's world,
// from every frame.
//
// - captureConsole off (the default): the page's console is its own (native
//   console.log) and nothing reaches consoleMessage;
// - a handler registered for the page's world gets a page-world user script's
//   messages from the top frame and from a frame;
// - captureConsole on: console messages arrive; off again: the console is
//   native on the next page and nothing more arrives.
//
//   tools/host-run.sh <prefix> <build> qml6 tests/console.qml
//
// Prints "console: PASS|FAIL <step>"; exits 0 when all passed.
import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    property int failures: 0
    property var steps: []
    property var consoleLines: []
    property var reports: []
    readonly property string page: "<body><iframe srcdoc='<p>frame</p>'></iframe><script>console.log('page says hello')</script></body>"

    function check(name, ok, detail) {
        console.warn("console: " + (ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " (" + detail + ")" : ""))
        if (!ok)
            failures++
    }

    function next() {
        if (steps.length === 0) {
            console.warn("console: " + (failures ? failures + " failure(s)" : "all passed"))
            Qt.exit(failures ? 1 : 0)
            return
        }
        steps.shift()()
    }

    // Loads the page afresh, waits for its frame's report, then fn().
    function loadPage(fn) {
        consoleLines = []
        reports = []
        view.done = fn
        view.loadHtml(page, "https://example.org/" + Date.now())
    }

    width: 400
    height: 400
    visible: true

    Timer {
        interval: 60000
        running: true
        onTriggered: {
            root.check("finished in time", false)
            Qt.exit(1)
        }
    }

    WebView {
        id: view

        property var done: null

        anchors.fill: parent
        onLoadingChanged: function(request) {
            if (request.status === LoadRequest.Succeeded && done)
                settle.restart()
        }
        onConsoleMessage: function(level, message, source) {
            root.consoleLines.push(message)
        }
        onScriptMessage: function(name, message) {
            if (name === "shipConsent")
                root.reports.push(message.frame)
        }
        Component.onCompleted: {
            registerScriptMessageHandler("shipConsent", "")
            addUserScript("window.webkit.messageHandlers.shipConsent.postMessage({ type: 'autoconsentDone', frame: window.top === window ? 'top' : 'frame' })",
                          "", WebView.DocumentEnd, true)
        }
    }

    Timer {
        id: settle

        interval: 700
        onTriggered: view.runJavaScript("String(/\\[native code\\]/.test(String(console.log)))", function(native) {
            const fn = view.done
            view.done = null
            fn(native === "true")
        })
    }

    Component.onCompleted: {
        steps = [
            function() {
                root.check("captureConsole is off by default", view.captureConsole === false)
                root.loadPage(function(native) {
                    root.check("the page's console is native", native)
                    root.check("nothing reaches consoleMessage", root.consoleLines.length === 0, root.consoleLines)
                    root.check("page-world handler: top frame", root.reports.indexOf("top") >= 0, root.reports)
                    root.check("page-world handler: subframe", root.reports.indexOf("frame") >= 0, root.reports)
                    root.next()
                })
            },
            function() {
                view.captureConsole = true
                root.loadPage(function(native) {
                    root.check("captured: console wrapped", !native)
                    root.check("captured: message arrives", root.consoleLines.indexOf("page says hello") >= 0, root.consoleLines)
                    root.next()
                })
            },
            function() {
                view.captureConsole = false
                root.loadPage(function(native) {
                    root.check("off again: console native", native)
                    root.check("off again: nothing arrives", root.consoleLines.length === 0, root.consoleLines)
                    root.check("off again: reports still arrive", root.reports.length >= 2, root.reports)
                    root.next()
                })
            }
        ]
        next()
    }
}
