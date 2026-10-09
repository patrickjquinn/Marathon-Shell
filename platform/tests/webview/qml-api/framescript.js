// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// A Gecko-style frame script for tst_webview_api.qml: answers "test:ping"
// with "test:pong" and the page's title.
addMessageListener("test:ping", function(message) {
    sendAsyncMessage("test:pong", { "title": content.document.title, "echo": message.data });
});
