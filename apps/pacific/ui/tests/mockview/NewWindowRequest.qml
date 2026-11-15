// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Mock of the web view's NewWindowRequest.
import QtQuick

QtObject {
    property url url
    property bool userInitiated: true
    property string frameName
    function openIn(view) {
        if (!view)
            return false
        view.load(url)
        return true
    }
}
