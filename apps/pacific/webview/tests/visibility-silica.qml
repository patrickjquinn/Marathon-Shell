// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Page visibility in a Silica (Keel) application, as Pacific's BrowserPage
// sets it up: tab delegates in a Repeater on a Page, created before the
// window is shown, the current one brought to the front, a page pushed over
// the browser and popped again. Needs Keel's QML modules on the import path
// (run-host-tests.sh passes KEEL_QML).
//
// Prints "visibility-silica: PASS|FAIL"; exits 0 when all passed.
pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica
import Shipwright.Pacific.WebView 1.0

ApplicationWindow {
    id: app

    property int current: -1
    property int failures: 0
    property var browserPage: null
    readonly property string page: "data:text/html;charset=utf-8,<body><script>"
        + "var n=0;(function f(){n++;requestAnimationFrame(f)})();</script></body>"

    function check(name, ok, detail) {
        console.warn("visibility-silica: " + (ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " (" + detail + ")" : ""))
        if (!ok)
            failures++
    }

    function after(ms, fn) {
        const t = Qt.createQmlObject("import QtQuick; Timer {}", app)
        t.interval = ms
        t.triggered.connect(function() { fn(); t.destroy() })
        t.start()
    }

    function measure(view, fn) {
        view.runJavaScript("window.__n0=n;window.__t0=performance.now()", function() {
            after(1000, function() {
                view.runJavaScript("JSON.stringify({s:document.visibilityState,hz:(n-window.__n0)*1000/(performance.now()-window.__t0)})",
                    function(r) { fn(JSON.parse(r)) })
            })
        })
    }

    function finish() {
        console.warn("visibility-silica: " + (failures ? failures + " failure(s)" : "all passed"))
        Qt.exit(failures ? 1 : 0)
    }

    initialPage: Component {
        Page {
            id: browser

            property alias tabs: repeater

            Component.onCompleted: app.browserPage = browser

            Repeater {
                id: repeater

                model: 2

                delegate: Item {
                    id: tab

                    required property int index
                    readonly property bool isCurrent: app.current === index
                    readonly property alias view: web

                    anchors.fill: parent
                    visible: isCurrent

                    WebView {
                        id: web

                        anchors.fill: parent
                        active: tab.isCurrent
                        url: app.page
                    }
                }
            }
        }
    }

    Component {
        id: coverPage

        Page {
            Label {
                anchors.centerIn: parent
                text: "Over the browser"
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: {
            app.current = 1
            app.after(1500, function() {
                const front = app.browserPage.tabs.itemAt(1).view
                const back = app.browserPage.tabs.itemAt(0).view
                app.measure(front, function(f) {
                    app.check("front tab visible", f.s === "visible", f.s)
                    app.check("front tab rAF >= 50 Hz", f.hz >= 50, Math.round(f.hz) + " Hz")
                    back.runJavaScript("document.visibilityState", function(s) {
                        app.check("background tab hidden", s === "hidden", s)
                        app.pageStack.push(coverPage, {}, PageStackAction.Immediate)
                        app.after(1500, function() {
                            front.runJavaScript("document.visibilityState", function(s2) {
                                app.check("covered by another page: hidden", s2 === "hidden", s2)
                                app.pageStack.pop(null, PageStackAction.Immediate)
                                app.after(1500, function() {
                                    app.measure(front, function(f2) {
                                        app.check("page popped: visible again", f2.s === "visible", f2.s)
                                        app.check("page popped: rAF >= 50 Hz", f2.hz >= 50, Math.round(f2.hz) + " Hz")
                                        app.finish()
                                    })
                                })
                            })
                        })
                    })
                })
            })
        }
    }

    Timer {
        interval: 60000
        running: true
        onTriggered: {
            console.warn("visibility-silica: FAIL timeout")
            Qt.exit(2)
        }
    }
}
