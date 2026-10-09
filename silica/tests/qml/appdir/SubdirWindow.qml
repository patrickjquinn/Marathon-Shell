// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// An app window in its own directory with a relative string initialPage, as
// in an app's main QML file. Used by tst_initialpage.qml.
import QtQuick 2.6
import Sailfish.Silica 1.0

ApplicationWindow {
    initialPage: "pages/SubPage.qml"
}
