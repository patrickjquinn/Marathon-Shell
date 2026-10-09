// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Test double of Qt WebEngine's FileDialogRequest.
import QtQml 2.0

QtObject {
    enum FileMode { FileModeOpen, FileModeOpenMultiple, FileModeUploadFolder, FileModeSave }

    property int mode
    property var acceptedMimeTypes: []
    property string defaultFileName
    property bool accepted
    property string result
    property var files: []

    function dialogAccept(list) { result = "accepted"; files = list }
    function dialogReject() { result = "rejected" }
}
