// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Test double of Qt WebEngine's AuthenticationDialogRequest.
import QtQml 2.0

QtObject {
    enum AuthenticationType { AuthenticationTypeHTTP, AuthenticationTypeProxy }

    property int type
    property url url
    property string realm
    property string proxyHost
    property bool accepted
    property string result
    property string user
    property string password

    function dialogAccept(u, p) { result = "accepted"; user = u; password = p }
    function dialogReject() { result = "rejected" }
}
