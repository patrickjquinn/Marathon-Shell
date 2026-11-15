// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// End-to-end smoke test of Shipwright.Pacific.WebView with a real engine:
//
//   tools/host-run.sh <prefix> <build> qml6 tests/smoke.qml          (host)
//   /usr/libexec/pacific/pacific-env.sh qml6 smoke.qml                (phone)
//
// A visible view and a headless one load a local test page; the agent API,
// trusted input, find, thumbnails, session state, discard and reload are
// exercised in turn. Prints "smoke: PASS <step>" / "smoke: FAIL <step>" and
// exits 0 only when every step passed.
import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    readonly property string page: "data:text/html;charset=utf-8," + encodeURIComponent("<!doctype html><title>smoke</title><meta name=viewport content='width=device-width'>" + "<body style='font:20px sans-serif'><h1 id=h>Pacific smoke</h1><p>alpha beta alpha gamma alpha</p>" + "<form id=f onsubmit='document.title=\"submitted:\"+document.getElementById(\"em\").value;return false'>" + "<input id=em type=email placeholder=Email> <select id=s><option value=a>A</option><option value=b>B</option></select>" + "<button id=go type=submit>Go</button></form>" + "<button id=tap onclick='document.title=\"tapped:\"+event.isTrusted' style='width:200px;height:80px'>Tap me</button>" + "<script>window.pageSecret = 42; window.__pacificAgent = 'spoofed';</script></body>")
    property var steps: []
    property int failures: 0
    property var snap: null

    function check(name, ok, detail) {
        console.warn("smoke: " + (ok ? "PASS " : "FAIL ") + name + (detail ? " (" + detail + ")" : ""));
        if (!ok)
            failures++;
    }

    function idFor(predicate) {
        for (let i = 0; i < snap.elements.length; i++) {
            if (predicate(snap.elements[i]))
                return snap.elements[i].id;
        }
        return "";
    }

    function next() {
        if (steps.length === 0) {
            console.warn("smoke: " + (failures ? failures + " failure(s)" : "all passed"));
            Qt.exit(failures ? 1 : 0);
            return;
        }
        const step = steps.shift();
        step();
    }

    function later(ms, fn) {
        const t = Qt.createQmlObject("import QtQuick; Timer { repeat: false }", root);
        t.interval = ms;
        t.triggered.connect(function () {
            fn();
            t.destroy();
        });
        t.start();
    }

    function pageTitle(view, fn) {
        view.runJavaScript("document.title", fn);
    }

    width: 540
    height: 960
    visible: true

    Component.onCompleted: {
        steps = [function () {
                view.agentSnapshot({
                    limit: 50,
                    text: 200
                }, function (result, error) {
                    snap = result;
                    check("snapshot", !error && result && result.title === "smoke" && result.elements.length >= 4, error || (result ? result.elements.length + " elements" : "no result"));
                    check("isolated world", result && result.text.indexOf("Pacific smoke") >= 0);
                    next();
                });
            }, function () {
                view.runJavaScriptInWorld("typeof window.pageSecret", "pacific", function (result) {
                    check("page globals invisible to the pacific world", result === "undefined", result);
                    view.runJavaScript("typeof window.__pacificAgent", function (r2) {
                        check("agent invisible to the page world", r2 === "string", r2);
                        next();
                    });
                });
            }, function () {
                const id = idFor(function (e) {
                    return e.label === "Tap me";
                });
                view.agentClick(id, function (result) {
                    check("agentClick dispatched", result && result.ok && result.method === "tap", JSON.stringify(result));
                    later(600, function () {
                        pageTitle(view, function (t) {
                            check("native tap is trusted", t === "tapped:true", t);
                            next();
                        });
                    });
                });
            }, function () {
                const id = idFor(function (e) {
                    return e.type === "email";
                });
                view.agentType(id, "pilot@example.org", function (result) {
                    later(300, function () {
                        view.runJavaScript("document.getElementById('em').value", function (v) {
                            check("agentType", v === "pilot@example.org", v);
                            next();
                        });
                    });
                });
            }, function () {
                const id = idFor(function (e) {
                    return e.tag === "select";
                });
                view.agentSetValue(id, "B", function (result) {
                    check("agentSetValue select", result && result.ok && result.value === "b", JSON.stringify(result));
                    next();
                });
            }, function () {
                const id = idFor(function (e) {
                    return e.type === "email";
                });
                view.agentSubmit(id, function (result) {
                    later(300, function () {
                        pageTitle(view, function (t) {
                            check("agentSubmit", t === "submitted:pilot@example.org", t);
                            next();
                        });
                    });
                });
            }, function () {
                view.findResult.connect(function onFound(count) {
                    view.findResult.disconnect(onFound);
                    check("find in page", count === 3, count);
                    view.stopFind();
                    next();
                });
                view.findText("alpha", false);
            }, function () {
                view.saveThumbnail(thumbPath, 270, 480, function (ok, path) {
                    check("thumbnail", ok, path);
                    next();
                });
            }, function () {
                const state = view.sessionState();
                check("session state", state.length > 20, state.length + " bytes");
                next();
            }, function () {
                headlessView.pageText(1000, function (text) {
                    check("headless view loads and reads", typeof text === "string" && text.indexOf("Pacific smoke") >= 0, String(text).slice(0, 40));
                    next();
                });
            }, function () {
                view.webProcessTerminated.connect(function onGone(reason) {
                    view.webProcessTerminated.disconnect(onGone);
                    check("discard terminates the web process", reason === WebView.TerminatedByApi && !view.webProcessRunning, "reason " + reason);
                    view.loadingChanged.connect(function onLoad(request) {
                        if (request.status !== LoadRequest.Succeeded)
                            return;
                        view.loadingChanged.disconnect(onLoad);
                        check("reload after discard", view.webProcessRunning);
                        next();
                    });
                    view.reload();
                });
                view.discard();
            },];
    }

    property string thumbPath: Qt.platform.os === "linux" ? "/tmp/pacific-smoke-thumb.png" : "thumb.png"
    property int loaded: 0

    function started() {
        if (++loaded === 2)
            later(300, next);
    }

    WebView {
        id: view

        anchors.fill: parent
        url: root.page
        onLoadingChanged: function (request) {
            if (request.status === LoadRequest.Succeeded && root.loaded < 2)
                root.started();
        }
    }

    WebView {
        id: headlessView

        headless: true
        profile: WebEngine.privateProfile
        url: root.page
        onLoadingChanged: function (request) {
            if (request.status === LoadRequest.Succeeded && root.loaded < 2)
                root.started();
        }
    }

    Timer {
        interval: 60000
        running: true
        onTriggered: {
            console.warn("smoke: FAIL timeout");
            Qt.exit(2);
        }
    }
}
