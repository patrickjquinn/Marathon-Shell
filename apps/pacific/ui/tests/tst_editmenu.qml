// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A long press in a web text field: the edit bar offers what the field
// allows and runs the view's editing commands.

import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Shipwright.Pacific.WebView 1.0
import "../qml/components"

Item {
    width: 480
    height: 800

    WebView {
        id: view
        width: 480
        height: 800
    }

    EditMenu {
        id: menu
        anchors.fill: parent
    }

    TestCase {
        name: "EditMenu"
        when: windowShown

        function field(extra) {
            var info = {
                editable: true,
                editMenu: true,
                hasText: true,
                selected: false,
                x: 200,
                y: 300
            };
            for (var k in extra)
                info[k] = extra[k];
            return info;
        }

        function tap(name) {
            var action = findChild(menu, name);
            verify(action.visible, name);
            tryVerify(function () {
                return !isPolishScheduled(action.parent);
            });
            mouseClick(action);
        }

        function lastCall() {
            return view.calls[view.calls.length - 1];
        }

        function init() {
            view.calls = [];
            Clipboard.text = "pasted";
        }

        function test_selectAllThenCopy() {
            menu.open({
                webView: view
            }, field({}));
            verify(menu.visible);
            verify(!findChild(menu, "copy").visible);
            tap("selectAll");
            compare(lastCall().name, "executeEditingCommand");
            compare(lastCall().args[0], WebView.SelectAll);
            verify(menu.visible);
            verify(!findChild(menu, "selectAll").visible);
            tap("copy");
            compare(lastCall().args[0], WebView.Copy);
            verify(!menu.visible);
        }

        function test_cutASelection() {
            menu.open({
                webView: view
            }, field({
                selected: true
            }));
            tap("cut");
            compare(lastCall().args[0], WebView.Cut);
            verify(!menu.visible);
        }

        function test_paste() {
            menu.open({
                webView: view
            }, field({
                hasText: false
            }));
            verify(!findChild(menu, "selectAll").visible);
            tap("paste");
            compare(lastCall().args[0], WebView.Paste);
        }

        function test_passwordOffersPasteOnly() {
            menu.open({
                webView: view
            }, field({
                secret: true,
                selected: true
            }));
            verify(menu.visible);
            verify(!findChild(menu, "selectAll").visible);
            verify(!findChild(menu, "cut").visible);
            verify(!findChild(menu, "copy").visible);
            verify(findChild(menu, "paste").visible);
            Clipboard.text = "";
            menu.open({
                webView: view
            }, field({
                secret: true
            }));
            verify(!menu.visible);
        }

        function test_tapElsewhereCloses() {
            menu.open({
                webView: view
            }, field({}));
            mouseClick(menu, 20, 780);
            verify(!menu.visible);
        }
    }
}
