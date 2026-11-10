// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView's dialogs over the Qt WebEngine test double: the page's
// requests (JavaScript alert, confirm, prompt; HTTP authentication; a
// geolocation permission, remembered when "don't ask again" is ticked; a
// link's context menu; a file upload) open sailfish-components-webview's
// popups and pickers through Keel's message bridge, and the answers reach
// the requests. An app's popupProvider replaces a dialog. Sailfish.WebView.
// Controls' PermissionModel reads and edits the same remembered permissions.
import QtQuick 2.6
import QtTest 1.0
import Sailfish.Silica 1.0
import Sailfish.WebView 1.0
import Sailfish.WebView.Controls 1.0
import QtWebEngine 1.10 as Fake

Item {
    id: root
    width: 540
    height: 960
    property alias pageStack: win.pageStack
    property alias __silica_applicationwindow_instance: win

    ApplicationWindow {
        id: win
        anchors.fill: parent
        initialPage: Component { Page { } }
    }

    Component {
        id: webPage
        WebViewPage {
            property alias view: view
            WebView {
                id: view
                anchors.fill: parent
                url: "https://example.org/a"
            }
        }
    }

    PermissionModel { id: perms; host: "perm.example.org" }

    Component { id: jsRequest; Fake.JavaScriptDialogRequest { } }
    Component { id: authRequest; Fake.AuthenticationDialogRequest { } }
    Component { id: menuRequest; Fake.ContextMenuRequest { } }
    Component { id: fileRequest; Fake.FileDialogRequest { } }

    // An app's own alert dialog (PopupProvider.alertPopup).
    Component {
        id: customAlert
        Dialog {
            property string text
            property string acceptText
            property string cancelText
            property bool preventDialogsVisible
            property bool preventDialogsPrefillValue
            property bool preventDialogsValue
            property bool custom: true
            DialogHeader { }
        }
    }

    TestCase {
        name: "WebViewPopups"
        when: windowShown

        function openPage() {
            tryCompare(win.pageStack, "busy", false)
            var p = win.pageStack.push(webPage, {}, PageStackAction.Immediate)
            tryCompare(win.pageStack, "busy", false)
            tryVerify(function() { return p.view._backend !== null && p.view._backend.view !== null })
            return p
        }

        function topDialog(page) {
            tryVerify(function() { return win.pageStack.currentPage !== page && !win.pageStack.busy }, 5000)
            return win.pageStack.currentPage
        }

        function closeTo(page) {
            tryCompare(win.pageStack, "busy", false)
            win.pageStack.pop(page, PageStackAction.Immediate)
            tryCompare(win.pageStack, "busy", false)
        }

        function test_alert_confirm_prompt() {
            var p = openPage()
            var view = p.view._backend.view

            var alert = jsRequest.createObject(root, { "type": Fake.JavaScriptDialogRequest.DialogTypeAlert,
                                                       "message": "Hello from the page" })
            view.javaScriptDialogRequested(alert)
            verify(alert.accepted)
            var d = topDialog(p)
            compare(d.text, "Hello from the page")
            d.accept()
            tryCompare(alert, "result", "accepted")
            tryCompare(win.pageStack, "currentPage", p)

            var confirm = jsRequest.createObject(root, { "type": Fake.JavaScriptDialogRequest.DialogTypeConfirm,
                                                         "message": "Sure?" })
            view.javaScriptDialogRequested(confirm)
            d = topDialog(p)
            compare(d.text, "Sure?")
            d.reject()
            tryCompare(confirm, "result", "rejected")

            var prompt = jsRequest.createObject(root, { "type": Fake.JavaScriptDialogRequest.DialogTypePrompt,
                                                        "message": "Name?", "defaultText": "Ada" })
            view.javaScriptDialogRequested(prompt)
            d = topDialog(p)
            compare(d.defaultValue, "Ada")
            d.value = "Grace"
            d.accept()
            tryCompare(prompt, "result", "accepted")
            compare(prompt.text, "Grace")
            closeTo(null)
        }

        function test_authentication() {
            var p = openPage()
            var view = p.view._backend.view
            var request = authRequest.createObject(root, { "url": "https://secure.example.org/x", "realm": "Members" })
            view.authenticationDialogRequested(request)
            var d = topDialog(p)
            compare(d.hostname, "secure.example.org")
            compare(d.realm, "Members")
            verify(d.usernameVisible)
            d.usernameValue = "ada"
            d.passwordValue = "secret"
            d.accept()
            tryCompare(request, "result", "accepted")
            compare(request.user, "ada")
            compare(request.password, "secret")
            closeTo(null)
        }

        function test_geolocation_permission_remembered() {
            // KEEL_WEBVIEW_PERMISSIONS starts empty (the ctest fixture).
            var p = openPage()
            var view = p.view._backend.view
            view.featurePermissionRequested("https://maps.example.org", Fake.WebEngineView.Geolocation)
            var d = topDialog(p)
            compare(d.host, "maps.example.org")
            d.rememberValue = true
            d.accept()
            tryCompare(view, "grants", [["https://maps.example.org", Fake.WebEngineView.Geolocation, true]])
            tryCompare(win.pageStack, "currentPage", p)
            // Remembered: answered without a dialog.
            view.featurePermissionRequested("https://maps.example.org", Fake.WebEngineView.Geolocation)
            compare(view.grants.length, 2)
            compare(view.grants[1][2], true)
            compare(win.pageStack.currentPage, p)
            // Not a feature Sailfish's WebView asks about: denied.
            view.featurePermissionRequested("https://maps.example.org", Fake.WebEngineView.Notifications)
            compare(view.grants[2][2], false)
            closeTo(null)
        }

        function test_link_context_menu() {
            var p = openPage()
            var view = p.view._backend.view
            var request = menuRequest.createObject(root, { "linkUrl": "https://example.org/linked",
                                                           "linkText": " A link ", "position": Qt.point(10, 20) })
            view.contextMenuRequested(request)
            verify(request.accepted)
            var menu = p.view._backend.popupOpenerForTests.contextMenu
            verify(menu !== null)
            compare(menu.linkHref, "https://example.org/linked")
            compare(menu.linkTitle, "A link")
            compare(menu.linkProtocol, "http")
            tryCompare(menu, "active", true)
            // Plain text: Qt WebEngine's own menu is suppressed, nothing opens.
            var plain = menuRequest.createObject(root, { })
            view.contextMenuRequested(plain)
            verify(plain.accepted)
            closeTo(null)
        }

        function test_file_upload_opens_picker() {
            var p = openPage()
            var view = p.view._backend.view
            var request = fileRequest.createObject(root, { "mode": Fake.FileDialogRequest.FileModeOpen,
                                                           "acceptedMimeTypes": ["image/*"] })
            view.fileDialogRequested(request)
            verify(request.accepted)
            var picker = topDialog(p)
            verify(String(picker).indexOf("ImagePicker") === 0 || picker.hasOwnProperty("selectedContent"),
                   String(picker))
            closeTo(null)
            // Saving is not offered by Sailfish's WebView: rejected.
            var save = fileRequest.createObject(root, { "mode": Fake.FileDialogRequest.FileModeSave })
            view.fileDialogRequested(save)
            compare(save.result, "rejected")
        }

        // Sailfish.WebView.Controls: PermissionModel's site permissions are
        // the ones the bridge answers with; TextSelectionController loads
        // (inert: Chromium draws its own selection handles).
        function test_controls() {
            var src = "import Sailfish.WebView.Controls 1.0; PermissionModel { host: 'perm.example.org' }"
            perms.add("perm.example.org", "geolocation", 1)
            compare(perms.count, 1)
            var again = Qt.createQmlObject(src, root)
            tryCompare(again, "count", 1)
            var p = openPage()
            var view = p.view._backend.view
            view.featurePermissionRequested("https://perm.example.org", Fake.WebEngineView.Geolocation)
            compare(view.grants.length, 1)
            compare(view.grants[0][2], true)
            compare(win.pageStack.currentPage, p)
            perms.removeAllForPermissionType("geolocation")
            compare(perms.count, 0)
            var empty = Qt.createQmlObject(src, root)
            wait(50)
            compare(empty.count, 0)
            var selection = Qt.createQmlObject(
                        "import Sailfish.WebView.Controls 1.0; TextSelectionController { }", p)
            verify(!selection.active)
            verify(!selection._canCall)
            again.destroy(); empty.destroy(); selection.destroy()
            closeTo(null)
        }

        function test_app_popup_provider() {
            var p = openPage()
            var provider = Qt.createQmlObject("import Sailfish.WebView.Popups 1.0; PopupProvider { }", p)
            provider.alertPopup = { "type": "dialog", "component": customAlert }
            p.view.popupProvider = provider
            var alert = jsRequest.createObject(root, { "type": Fake.JavaScriptDialogRequest.DialogTypeAlert,
                                                       "message": "Custom" })
            p.view._backend.view.javaScriptDialogRequested(alert)
            var d = topDialog(p)
            verify(d.custom)
            compare(d.text, "Custom")
            d.accept()
            tryCompare(alert, "result", "accepted")
            closeTo(null)
        }
    }
}
