// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Mock of the web view's NavigationRequest.
import QtQuick

QtObject {
    enum NavigationType { LinkClicked, FormSubmitted, BackForward, Reload, FormResubmitted, Other }
    enum Action { Accept, Ignore, Download }
    property url url
    property int navigationType: NavigationRequest.LinkClicked
    property bool userInitiated: true
    property bool redirect: false
    property int action: NavigationRequest.Accept
    function accept() { action = NavigationRequest.Accept }
    function ignore() { action = NavigationRequest.Ignore }
    function download() { action = NavigationRequest.Download }
}
