// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// User-script test: scripts added for the page's own world (no world name,
// as the browser adds autoconsent) and for a named world both run, and the
// named one stays invisible to the page. An empty world once crashed the app
// on its first tab (webkit_user_script_new_for_world() requires a name).
//
//   tools/host-run.sh <prefix> <build> qml6 tests/userscripts.qml
//
// Prints "userscripts: PASS|FAIL <step>"; exits 0 when all passed.
import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    property int failures: 0
    property bool started: false

    function check(name, ok, detail) {
        console.warn("userscripts: " + (ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " (" + detail + ")" : ""));
        if (!ok)
            failures++;
    }

    function finish() {
        console.warn("userscripts: " + (failures ? failures + " failure(s)" : "all passed"));
        Qt.exit(failures ? 1 : 0);
    }

    width: 540
    height: 600
    visible: true

    Timer {
        interval: 30000
        running: true
        onTriggered: {
            root.check("finished in time", false);
            root.finish();
        }
    }

    WebView {
        id: view

        anchors.fill: parent

        Component.onCompleted: {
            addUserScript("window.__pageWorld = 'yes';", "", WebView.DocumentStart, false);
            addUserScript("window.__namedWorld = 'yes';", "pacific-test", WebView.DocumentStart, false);
            root.check("scripts added without crashing", true);
            load("data:text/html;charset=utf-8,<body>user scripts</body>");
        }

        onLoadingChanged: function (request) {
            if (request.status !== LoadRequest.Succeeded || root.started)
                return;
            root.started = true;
            view.runJavaScript("[String(window.__pageWorld), String(window.__namedWorld)].join(',')", function (result, error) {
                root.check("page-world script ran", String(result).split(",")[0] === "yes", result || error);
                root.check("named-world script hidden from the page", String(result).split(",")[1] === "undefined", result || error);
                view.runJavaScriptInWorld("String(window.__namedWorld)", "pacific-test", function (r, e) {
                    root.check("named-world script ran in its world", r === "yes", r || e);
                    root.finish();
                });
            });
        }
    }
}
