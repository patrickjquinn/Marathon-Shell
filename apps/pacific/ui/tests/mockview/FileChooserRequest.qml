// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Mock of the web view's FileChooserRequest.
import QtQuick

QtObject {
    property var mimeTypes: []
    property bool multiple: false
    property var selectedFiles: []
    property bool answered: false
    function select(files) { selectedFiles = files; answered = true }
    function cancel() { answered = true }
}
