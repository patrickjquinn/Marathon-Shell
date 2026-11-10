// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Test double of Qt WebEngine's ColorDialogRequest.
import QtQuick 2.0

QtObject {
    property color color
    property bool accepted
    property string result
    property color chosen

    function dialogAccept(c) { result = "accepted"; chosen = c }
    function dialogReject() { result = "rejected" }
}
