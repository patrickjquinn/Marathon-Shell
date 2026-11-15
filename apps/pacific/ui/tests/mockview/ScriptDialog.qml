// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Mock of the web view's ScriptDialog.
import QtQuick

QtObject {
    enum Type { Alert, Confirm, Prompt, BeforeUnload }
    property int type: ScriptDialog.Alert
    property string message
    property string defaultText
    property bool accepted: false
    property string text
    signal close()
    function accept(t) { accepted = true; text = t || ""; close() }
    function reject() { accepted = false; close() }
}
