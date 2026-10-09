// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
import QtQuick 2.6

QtObject {
    enum NavigationType { LinkClickedNavigation, TypedNavigation, FormSubmittedNavigation,
                          BackForwardNavigation, ReloadNavigation, OtherNavigation, RedirectNavigation }
    property url url
    property int navigationType
    property bool isMainFrame: true
    property string result
    function accept() { result = "accepted" }
    function reject() { result = "rejected" }
}
