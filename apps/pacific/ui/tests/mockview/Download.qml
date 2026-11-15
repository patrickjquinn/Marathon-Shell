// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Mock of the web view's Download: 2.5 MB/s.
import QtQuick

QtObject {
    id: download
    enum State { InProgress, Finished, Failed, Cancelled }
    property url url
    property string suggestedFilename
    property string destination
    property string mimeType: "application/octet-stream"
    property real progress: 0
    property double receivedBytes: 0
    property double totalBytes: 1048576
    property int state: Download.InProgress
    property string errorString
    function cancel() { state = Download.Cancelled }
    property Timer _timer: Timer {
        interval: 100
        repeat: true
        running: download.state === Download.InProgress
        onTriggered: {
            download.receivedBytes = Math.min(download.totalBytes, download.receivedBytes + 262144)
            download.progress = download.receivedBytes / download.totalBytes
            if (download.progress >= 1)
                download.state = Download.Finished
        }
    }
}
