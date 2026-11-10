// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Test double of Qt WebEngine's JavaScriptDialogRequest: records the answer.
import QtQml 2.0

QtObject {
    enum DialogType { DialogTypeAlert, DialogTypeConfirm, DialogTypePrompt, DialogTypeBeforeUnload }

    property int type
    property string message
    property string defaultText
    property string title
    property url securityOrigin
    property bool accepted
    property string result
    property string text

    function dialogAccept(value) { result = "accepted"; text = value === undefined ? "" : value }
    function dialogReject() { result = "rejected" }
}
