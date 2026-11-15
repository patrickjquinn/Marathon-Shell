// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Plain Qt Quick chrome for the minibrowser (host and phone).
import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: window

    required property url startUrl
    required property string screenshotPath
    required property int settleMs
    required property bool printSnapshot
    required property bool headlessMode
    required property bool scriptInput
    property bool done: false

    function log(message) {
        console.warn("minibrowser: " + message);
    }

    function finish(code) {
        if (done)
            return;
        done = true;
        Qt.exit(code);
    }

    function afterLoad() {
        if (window.printSnapshot) {
            web.agentSnapshot({
                limit: 40,
                text: 400
            }, function (result, error) {
                if (error)
                    log("snapshot error " + error);
                console.warn("minibrowser: snapshot " + JSON.stringify(result));
                finish(error ? 1 : 0);
            });
        } else if (window.screenshotPath !== "") {
            settle.start();
        }
    }

    width: 540
    height: 960
    visible: !window.headlessMode
    color: "#20262c"
    title: web.title || "Pacific minibrowser"

    Timer {
        id: settle

        interval: window.settleMs
        onTriggered: {
            window.contentItem.grabToImage(function (image) {
                const ok = image.saveToFile(window.screenshotPath);
                window.log("screenshot " + (ok ? "saved " : "FAILED ") + window.screenshotPath);
                window.finish(ok ? 0 : 1);
            });
        }
    }

    Rectangle {
        id: bar

        height: 48
        width: parent.width
        color: "#2b333b"
        visible: !window.headlessMode

        Rectangle {
            width: parent.width * web.loadProgress / 100
            height: 3
            anchors.bottom: parent.bottom
            color: "#4fc3f7"
            visible: web.loading
        }

        Text {
            anchors.fill: parent
            anchors.margins: 12
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
            color: "white"
            text: (web.secure ? "\u{1F512} " : "") + web.url // i18n: literal
        }
    }

    WebView {
        id: web

        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        headless: window.headlessMode
        captureConsole: true
        inputMode: window.scriptInput ? WebView.ScriptInput : WebView.NativeInput
        url: window.startUrl
        focus: true

        onLoadingChanged: function (request) {
            const names = ["started", "redirected", "committed", "succeeded", "failed", "stopped"];
            window.log("load " + names[request.status] + " " + request.url + (request.errorString ? " (" + request.errorString + ")" : ""));
            if (request.status === LoadRequest.Succeeded)
                window.afterLoad();
            else if (request.status === LoadRequest.Failed && (window.printSnapshot || window.screenshotPath !== ""))
                window.finish(1);
        }
        onTitleChanged: window.log("title " + title)
        onIconChanged: window.log("icon " + icon)
        onConsoleMessage: function (level, message, source) {
            window.log("console." + level + " " + message);
        }
        onWebProcessTerminated: function (reason) {
            window.log("web process terminated, reason " + reason);
        }
        onEditableFocusedChanged: window.log("editable focus " + editableFocused + " purpose " + inputPurpose)
        onWebViewCreated: window.log("web view created, engine " + WebEngine.version + ", scale " + contentScale)
        onPermissionRequested: function (request) {
            window.log("permission " + request.kind + " from " + request.origin + ": denied");
            request.deny();
        }
        onNewWindowRequested: function (request) {
            window.log("new window " + request.url + ": opening here");
            web.url = request.url;
        }
        onScriptDialogRequested: function (dialog) {
            window.log("dialog " + dialog.type + ": " + dialog.message);
            dialog.accept();
        }
    }
}
