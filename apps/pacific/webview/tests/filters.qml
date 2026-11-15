// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Content-filter lifecycle, against tests/privacy-server.py on port 18089:
// two filters compiled and applied; both disabled (nothing blocked, the
// requests reach the server, contentFilters empty); enabled again from the
// store without compiling (blocked again); one removed (gone from the store,
// enabling it fails).
//
//   python3 tests/privacy-server.py 18089 &
//   tools/host-run.sh <prefix> <build> qml6 tests/filters.qml
//
// Prints "filters: PASS|FAIL"; exits 0 when all passed.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    property int failures: 0
    property var steps: []
    readonly property var profile: WebEngine.defaultProfile
    readonly property string ads: JSON.stringify([
        {
            trigger: {
                "url-filter": "/ads/"
            },
            action: {
                type: "block"
            }
        }
    ])
    readonly property string tracker: JSON.stringify([
        {
            trigger: {
                "url-filter": "tracker\\.js"
            },
            action: {
                type: "block"
            }
        }
    ])

    function check(name, ok, detail) {
        console.warn("filters: " + (ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " (" + detail + ")" : ""));
        if (!ok)
            failures++;
    }

    function next() {
        if (steps.length === 0) {
            console.warn("filters: " + (failures ? failures + " failure(s)" : "all passed"));
            Qt.exit(failures ? 1 : 0);
            return;
        }
        steps.shift()();
    }

    // Loads the page afresh; then fn(blocked count).
    function loadPage(fn) {
        view.done = fn;
        view.load("http://127.0.0.1:18089/page?" + Date.now());
    }

    width: 400
    height: 400
    visible: true

    WebView {
        id: view

        property var done: null

        anchors.fill: parent
        onLoadingChanged: function (request) {
            if (request.status !== LoadRequest.Succeeded || !done)
                return;
            const fn = done;
            done = null;
            settle.fn = fn;
            settle.start();
        }
    }

    Timer {
        id: settle

        property var fn: null

        interval: 800
        onTriggered: fn(view.blockedRequestCount)
    }

    Component.onCompleted: {
        steps = [function () {
                root.profile.compileContentFilter("test-ads", root.ads, function (ok, error) {
                    root.check("compile ads", ok, error);
                    root.profile.compileContentFilter("test-tracker", root.tracker, function (ok2, error2) {
                        root.check("compile tracker", ok2, error2);
                        next();
                    });
                });
            }, function () {
                loadPage(function (blocked) {
                    root.check("both filters block", blocked === 3, blocked);
                    next();
                });
            }, function () {
                root.profile.disableContentFilter("test-ads");
                root.profile.disableContentFilter("test-tracker");
                root.check("disabled: contentFilters empty", root.profile.contentFilters.length === 0, root.profile.contentFilters.join(","));
                loadPage(function (blocked) {
                    root.check("disabled: nothing blocked", blocked === 0, blocked);
                    const xhr = new XMLHttpRequest();
                    xhr.open("GET", "http://127.0.0.1:18089/log");
                    xhr.onreadystatechange = function () {
                        if (xhr.readyState !== XMLHttpRequest.DONE)
                            return;
                        const paths = JSON.parse(xhr.responseText).map(function (e) {
                            return e.path;
                        });
                        root.check("disabled: the formerly blocked requests go through", paths.indexOf("/ads/banner.png") >= 0 && paths.indexOf("/tracker.js") >= 0, paths.join(" "));
                        next();
                    };
                    xhr.send();
                });
            }, function () {
                root.profile.storedContentFilters(function (ids) {
                    root.check("disabled filters stay in the store", ids.indexOf("test-ads") >= 0 && ids.indexOf("test-tracker") >= 0, ids.join(","));
                    next();
                });
            }, function () {
                root.profile.enableContentFilter("test-ads", function (ok, error) {
                    root.check("enabled again from the store", ok, error);
                    root.profile.enableContentFilter("test-tracker", function (ok2, error2) {
                        root.check("enabled again from the store (2)", ok2, error2);
                        loadPage(function (blocked) {
                            root.check("re-enabled: blocks again", blocked === 3, blocked);
                            next();
                        });
                    });
                });
            }, function () {
                // Disable while a load is still running: the load must not
                // bring it back.
                root.profile.enableContentFilter("test-tracker", function (ok) {
                    root.check("enable overtaken by a disable is dropped", !ok);
                    root.check("removed filter stays removed", root.profile.contentFilters.indexOf("test-tracker") < 0, root.profile.contentFilters.join(","));
                    next();
                });
                root.profile.disableContentFilter("test-tracker");
            }, function () {
                root.profile.removeContentFilter("test-ads", function (ok, error) {
                    root.check("remove (delete)", ok, error);
                    root.profile.storedContentFilters(function (ids) {
                        root.check("deleted: gone from the store", ids.indexOf("test-ads") < 0, ids.join(","));
                        root.profile.enableContentFilter("test-ads", function (ok2) {
                            root.check("deleted: enabling it fails", !ok2);
                            root.profile.removeContentFilter("test-tracker", function () {
                                next();
                            });
                        });
                    });
                });
            },];
        next();
    }

    Timer {
        interval: 60000
        running: true
        onTriggered: {
            console.warn("filters: FAIL timeout");
            Qt.exit(2);
        }
    }
}
