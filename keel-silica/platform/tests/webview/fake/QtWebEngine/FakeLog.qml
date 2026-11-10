// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Test double only: what the fake QtWebEngine saw, for the tests.
pragma Singleton
import QtQuick 2.6

QtObject {
    property var views: []
    property var profiles: []
    property var scripts: []
    property var worldScripts: []
}
