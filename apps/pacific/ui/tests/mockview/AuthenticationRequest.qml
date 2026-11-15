// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Mock of the web view's AuthenticationRequest.
import QtQuick

QtObject {
    property string host
    property int port: 443
    property string realm
    property bool proxy: false
    property bool retry: false
    property bool answered: false
    function authenticate(user, password, remember) {
        answered = true;
    }
    function cancel() {
        answered = true;
    }
}
