// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Content-blocker reporting and Global Privacy Control, against a local
// server (tests/privacy-server.py, started by the caller on port 18089):
//
//   python3 tests/privacy-server.py 18089 &
//   tools/host-run.sh <prefix> <build> qml6 tests/privacy.qml
//
// A content filter blocks /ads/ and tracker.js: the view must count three
// blocked requests and name them, the server must never see them, and every
// request it does see must carry Sec-GPC: 1. Prints "privacy: PASS|FAIL".
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    property int failures: 0
    property var blocked: []

    function check(name, ok, detail) {
        console.warn("privacy: " + (ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " (" + detail + ")" : ""))
        if (!ok)
            failures++
    }

    width: 400
    height: 400
    visible: true

    Component.onCompleted: WebEngine.defaultProfile.compileContentFilter("privacy-test", JSON.stringify([
        { trigger: { "url-filter": "/ads/" }, action: { type: "block" } },
        { trigger: { "url-filter": "tracker\\.js" }, action: { type: "block" } }
    ]), function(ok, error) {
        root.check("filter compiled", ok, error)
        loader.active = true
    })

    Loader {
        id: loader

        active: false
        anchors.fill: parent
        sourceComponent: WebView {
            id: view

            url: "http://127.0.0.1:18089/page"
            onBlockedRequest: function(url) {
                root.blocked.push(String(url))
            }
            onLoadingChanged: function(request) {
                if (request.status !== LoadRequest.Succeeded)
                    return
                settle.view = view
                settle.start()
            }
        }
    }

    Timer {
        id: settle

        property var view: null

        interval: 1500
        onTriggered: {
            const v = view
            root.check("GPC on by default", v.profile.globalPrivacyControl === true)
            root.check("blockedRequestCount", v.blockedRequestCount === 3, v.blockedRequestCount)
            root.check("blockedRequest urls", root.blocked.length === 3
                       && root.blocked.join(" ").indexOf("/ads/banner.png") >= 0
                       && root.blocked.join(" ").indexOf("/tracker.js") >= 0, root.blocked.join(" "))
            v.runJavaScript("navigator.globalPrivacyControl", function(g) {
                root.check("navigator.globalPrivacyControl", g === true, g)
                const xhr = new XMLHttpRequest()
                xhr.open("GET", "http://127.0.0.1:18089/log")
                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE)
                        return
                    const seen = JSON.parse(xhr.responseText)
                    const paths = seen.map(function(s) { return s.path })
                    root.check("blocked requests never sent", paths.join(" ").indexOf("/ads/") < 0
                               && paths.indexOf("/tracker.js") < 0, paths.join(" "))
                    root.check("Sec-GPC: 1 on every request", seen.length >= 2 && seen.every(function(s) { return s.gpc === "1" }),
                               JSON.stringify(seen))
                    console.warn("privacy: " + (root.failures ? root.failures + " failure(s)" : "all passed"))
                    Qt.exit(root.failures ? 1 : 0)
                }
                xhr.send()
            })
        }
    }

    Timer {
        interval: 30000
        running: true
        onTriggered: {
            console.warn("privacy: FAIL timeout")
            Qt.exit(2)
        }
    }
}
