// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Keel (Sailfish Silica on Qt 6) chrome for the minibrowser, for the phone:
// pacific-minibrowser --silica [url]. The keyboard shrinks the page, so a
// focused field stays visible (the view scrolls it back into sight).
pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica
import Shipwright.Pacific.WebView 1.0

ApplicationWindow {
    id: app

    required property url startUrl
    required property string screenshotPath
    required property int settleMs
    required property bool printSnapshot
    required property bool headlessMode
    required property bool scriptInput

    function log(message) {
        console.warn("minibrowser: " + message)
    }

    initialPage: Component {
        Page {
            id: page

            allowedOrientations: Orientation.All

            WebView {
                id: web

                anchors.top: parent.top
                width: parent.width
                height: parent.height - (Qt.inputMethod.visible ? Qt.inputMethod.keyboardRectangle.height : 0)
                - toolbar.height
                // The view follows the application state itself.
                active: true
                captureConsole: true
                inputMode: app.scriptInput ? WebView.ScriptInput : WebView.NativeInput
                url: app.startUrl

                onLoadingChanged: function(request) {
                    app.log("load " + request.status + " " + request.url + " " + request.errorString)
                }
                onConsoleMessage: function(level, message) {
                    app.log("console." + level + " " + message)
                }
                onWebProcessTerminated: function(reason) {
                    app.log("web process terminated " + reason)
                }
                onEditableFocusedChanged: app.log("editable focus " + editableFocused + " purpose " + inputPurpose
                                                  + " cursor " + cursorRectangle)
                onPermissionRequested: function(request) {
                    app.log("permission " + request.kind + " " + request.origin)
                    request.allow()
                }
                onSelectMenuRequested: function(options, selectedIndex) {
                    app.log("select menu, " + options.length + " options; picking the next one")
                    web.selectMenuOption((selectedIndex + 1) % options.length)
                }
                onInputPickerRequested: function(type, value) {
                    app.log("picker " + type + " " + value)
                    web.cancelInputPicker()
                }
            }

            Row {
                id: toolbar

                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.itemSizeSmall

                IconButton {
                    icon.source: "image://theme/icon-m-back"
                    enabled: web.canGoBack
                    onClicked: web.goBack()
                }
                IconButton {
                    icon.source: web.loading ? "image://theme/icon-m-reset" : "image://theme/icon-m-refresh"
                    onClicked: web.loading ? web.stop() : web.reload()
                }
                Label {
                    width: parent.width - 2 * Theme.itemSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                    truncationMode: TruncationMode.Fade
                    text: web.title || web.url
                }
            }
        }
    }
}
