// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Downloads, against a local server (tests/download-server.py, started by
// the caller on port 18090 with the directory below):
//
//   python3 tests/download-server.py 18090 /tmp/pacific-download-test &
//   tools/host-run.sh <prefix> <build> qml6 tests/downloads.qml
//
// An attachment opened in a view downloads. Its suggested file name, from
// the server's Content-Disposition, is known before the destination has to
// be chosen, so the app can name the file after it; and a destination the
// app has already claimed as an empty file (Pacific reserves its names that
// way) is written, not refused as existing.
import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    readonly property string dir: "/tmp/pacific-download-test"
    readonly property string name: "report-final.bin"
    property int failures: 0
    property var download: null

    function check(what, ok, detail) {
        console.warn("downloads: " + (ok ? "PASS " : "FAIL ") + what + (detail !== undefined ? " (" + detail + ")" : ""))
        if (!ok)
            failures++
    }

    function finish() {
        console.warn("downloads: " + (failures === 0 ? "all passed" : failures + " failure(s)"))
        Qt.exit(failures === 0 ? 0 : 1)
    }

    width: 400
    height: 400
    visible: true

    Connections {
        target: WebEngine.defaultProfile
        function onDownloadStarted(download) {
            root.download = download
            download.suggestedFilenameChanged.connect(function() {
                // The engine asks for the destination right after this: an
                // app chooses it here, from the server's name.
                root.check("suggested name from Content-Disposition", download.suggestedFilename === root.name,
                           download.suggestedFilename)
                download.destination = root.dir + "/" + download.suggestedFilename
            })
            download.stateChanged.connect(function() {
                if (download.state === Download.Finished) {
                    root.check("written to the claimed destination", download.destination === root.dir + "/" + root.name,
                               download.destination)
                    const xhr = new XMLHttpRequest()
                    xhr.open("GET", "http://127.0.0.1:18090/size?name=" + encodeURIComponent(root.name))
                    xhr.onreadystatechange = function() {
                        if (xhr.readyState !== XMLHttpRequest.DONE)
                            return
                        root.check("the whole file", xhr.responseText === "10000", xhr.responseText)
                        root.finish()
                    }
                    xhr.send()
                } else if (download.state === Download.Failed || download.state === Download.Cancelled) {
                    root.check("download finishes", false, download.errorString)
                    root.finish()
                }
            })
        }
    }

    WebView {
        anchors.fill: parent
        url: "http://127.0.0.1:18090/file"
    }

    Timer {
        interval: 20000
        running: true
        onTriggered: {
            root.check("download finishes in 20 s", false, root.download ? root.download.state : "never started")
            root.finish()
        }
    }
}
