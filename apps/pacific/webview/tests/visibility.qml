// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Page visibility, as a tabbed browser drives it (Pacific's BrowserPage):
// tabs are created in a Repeater, inactive and hidden, then one is brought
// to the front; tabs are switched; a headless background view is promoted
// into the window; the window's application state is not relied on.
//
//   tools/host-run.sh <prefix> <build> qml6 tests/visibility.qml
//
// For each step: the front tab's document.visibilityState is "visible" and
// requestAnimationFrame runs at >= 50 Hz; every background tab is "hidden".
// Prints "visibility: PASS|FAIL"; exits 0 when all passed.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    property int current: -1
    property int failures: 0
    property var steps: []
    property string saved: ""
    property var orphan: null

    Component {
        id: orphanComponent

        WebView {
            width: root.width
            height: root.height
            active: true
            url: root.page
        }
    }
    readonly property string page: "data:text/html;charset=utf-8,<title>t</title><body style='background:%23cde'>" + "<div id=d style='width:50px;height:50px;background:red;position:absolute'></div><script>" + "var n=0;(function f(){n++;document.getElementById('d').style.left=(n%25200)+'px';requestAnimationFrame(f)})();" + "</script></body>"

    function check(name, ok, detail) {
        console.warn("visibility: " + (ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " (" + detail + ")" : ""));
        if (!ok)
            failures++;
    }

    function after(ms, fn) {
        const t = Qt.createQmlObject("import QtQuick; Timer {}", root);
        t.interval = ms;
        t.triggered.connect(function () {
            fn();
            t.destroy();
        });
        t.start();
        return t;
    }

    // Visibility state and rAF rate of a view, over one second. A script
    // call that does not answer within 5 s is a failure, not a hang.
    function measure(view, fn) {
        let answered = false;
        const watchdog = after(5000, function () {
            if (!answered) {
                answered = true;
                fn({
                    s: "no answer from the page",
                    hz: 0
                });
            }
        });
        view.runJavaScript("window.__n0=n;window.__t0=performance.now();document.visibilityState", function (state0, error0) {
            after(1000, function () {
                view.runJavaScript("JSON.stringify({s:document.visibilityState,hz:(n-window.__n0)*1000/(performance.now()-window.__t0)})", function (r, error) {
                    if (answered)
                        return;
                    answered = true;
                    fn(r ? JSON.parse(r) : {
                        s: "script error: " + (error || error0),
                        hz: 0
                    });
                });
            });
        });
    }

    // Checks the front view and every other one, then runs the next step.
    function expect(label, front, others) {
        measure(front, function (f) {
            check(label + ": front visible", f.s === "visible", f.s);
            check(label + ": front rAF >= 50 Hz", f.hz >= 50, Math.round(f.hz) + " Hz");
            let pending = others.length;
            if (!pending)
                next();
            others.forEach(function (o) {
                o.runJavaScript("document.visibilityState", function (s) {
                    check(label + ": background hidden", s === "hidden", s);
                    if (--pending === 0)
                        next();
                });
            });
        });
    }

    function next() {
        if (steps.length === 0) {
            console.warn("visibility: " + (failures ? failures + " failure(s)" : "all passed"));
            Qt.exit(failures ? 1 : 0);
            return;
        }
        steps.shift()();
    }

    function tabView(i) {
        return tabs.itemAt(i).view;
    }

    width: 480
    height: 640
    visible: true

    Item {
        id: stack

        anchors.fill: parent

        // As BrowserPage: a delegate per tab, only the current one visible
        // and active; created with nothing current.
        Repeater {
            id: tabs

            model: 3

            delegate: Item {
                id: tab

                required property int index
                readonly property bool isCurrent: root.current === index
                readonly property alias view: web

                anchors.fill: parent
                visible: isCurrent

                WebView {
                    id: web

                    anchors.fill: parent
                    active: tab.isCurrent
                    url: root.page
                }
            }
        }
    }

    readonly property string grabPath: "/tmp/pacific-visibility-grab.png"

    // Reads a pixel of the window grab (Canvas can read image data).
    Canvas {
        id: probe

        property var onDone: null

        width: 1
        height: 1
        visible: false
        onImageLoaded: {
            const ctx = getContext("2d");
            const url = "file://" + root.grabPath;
            ctx.drawImage(url, -Math.round(root.width / 2), -Math.round(root.height * 0.75));
            const d = ctx.getImageData(0, 0, 1, 1).data;
            unloadImage(url);
            if (onDone)
                onDone([d[0], d[1], d[2]]);
        }
    }

    // A tab created hidden behind the others, with a static page.
    Loader {
        id: lateTab

        anchors.fill: parent
        active: false
        sourceComponent: Item {
            readonly property alias view: late

            anchors.fill: parent
            visible: false

            WebView {
                id: late

                anchors.fill: parent
                active: false
                // Static: nothing repaints after the first frame (the rAF loop only counts).
                url: "data:text/html,<body style='margin:0;background:%23123456'><script>var n=0;(function f(){n++;requestAnimationFrame(f)})()</script></body>"
            }
        }
    }

    // A background (headless) view, later promoted into the stack.
    WebView {
        id: background

        headless: true
        url: root.page
    }

    Component.onCompleted: {
        steps = [function () {
                current = 0;
                after(1500, next);
            }, function () {
                expect("first tab brought to front", tabView(0), [tabView(1), tabView(2)]);
            }, function () {
                current = 2;
                after(800, next);
            }, function () {
                expect("switched to third tab", tabView(2), [tabView(0), tabView(1)]);
            }, function () {
                current = 0;
                after(800, next);
            }, function () {
                expect("back to first tab", tabView(0), [tabView(1), tabView(2)]);
            }, function () {
                expect("headless view is hidden", tabView(0), [background]);
            },
            // As WebTab: a background tab is discarded (its WebProcess ends)
            // and its state saved; brought to the front it is woken from
            // the saved state while already active.
            function () {
                saved = tabView(1).sessionState();
                tabView(1).saveThumbnail("/tmp/pacific-visibility-thumb.png", 100, 100);
                tabView(1).discard();
                after(800, next);
            }, function () {
                current = 1;
                if (!tabView(1).webProcessRunning) {
                    tabView(1).restoreSessionState(saved);
                    tabView(1).reload();
                }
                after(3000, next);
            }, function () {
                expect("discarded tab woken in front", tabView(1), [tabView(0), tabView(2)]);
            },
            // Discarded while in front, reloaded in front.
            function () {
                tabView(1).discard();
                after(500, function () {
                    tabView(1).reload();
                    after(3000, next);
                });
            }, function () {
                expect("tab reloaded after discard in front", tabView(1), [tabView(0), tabView(2)]);
            },
            // Brought to front, then woken a moment later (wake on a timer).
            function () {
                tabView(2).discard();
                after(500, next);
            }, function () {
                current = 2;
                after(300, function () {
                    tabView(2).reload();
                    after(3000, next);
                });
            }, function () {
                expect("tab woken after activation", tabView(2), [tabView(0), tabView(1)]);
            }, function () {
                current = 0;
                after(800, next);
            }, function () {
                // Promote: into the window, in front, shown.
                current = -1;
                background.parent = stack;
                background.anchors.fill = stack;
                background.headless = false;
                background.active = true;
                after(1000, next);
            }, function () {
                expect("promoted view", background, [tabView(0), tabView(1), tabView(2)]);
            }, function () {
                check("pageVisible matches", background.pageVisible && !tabView(0).pageVisible);
                next();
            },
            // A tab created outside any window (as a model delegate can be),
            // active from the start, then put into the window.
            function () {
                background.active = false;
                background.visible = false;
                orphan = orphanComponent.createObject(null);
                after(800, function () {
                    orphan.parent = stack;
                    after(1500, next);
                });
            }, function () {
                expect("view created without a window, then shown", orphan, [background, tabView(0)]);
            },
            // Created hidden (a later tab behind the front one), its page
            // static, then shown: it must draw at once at its own size.
            function () {
                orphan.visible = false;
                orphan.active = false;
                lateTab.active = true;
                after(2500, function () {
                    lateTab.item.visible = true;
                    lateTab.item.view.active = true;
                    after(800, next);
                });
            }, function () {
                const v = lateTab.item.view;
                v.runJavaScript("JSON.stringify({w:innerWidth,h:innerHeight,s:document.visibilityState})", function (r) {
                    const m = JSON.parse(r);
                    const scale = v.contentScale;
                    // CSS px = item px (desktop, scale = device pixel
                    // ratio) or item px / scale (Sailfish OS, ratio 1).
                    check("created hidden: page sized to the view", (Math.abs(m.w - v.width) <= 2 && Math.abs(m.h - v.height) <= 2) || (Math.abs(m.w * scale - v.width) <= 2 && Math.abs(m.h * scale - v.height) <= 2), m.w + "x" + m.h + " CSS px for a " + v.width + "x" + v.height + " item at scale " + scale);
                    root.contentItem.grabToImage(function (image) {
                        image.saveToFile(root.grabPath);
                        probe.onDone = function (c) {
                            check("created hidden: drawn when shown", c[0] === 0x12 && c[1] === 0x34 && c[2] === 0x56, c.join(","));
                            expect("created hidden, then shown", v, [orphan, background, tabView(0)]);
                        };
                        probe.loadImage("file://" + root.grabPath);
                    });
                });
            },];
        after(2000, next);
    }

    Timer {
        interval: 120000
        running: true
        onTriggered: {
            console.warn("visibility: FAIL timeout");
            Qt.exit(2);
        }
    }
}
