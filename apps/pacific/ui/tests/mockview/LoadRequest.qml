// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// Mock of the web view's LoadRequest.
import QtQuick

QtObject {
    enum Status { Started, Redirected, Committed, Succeeded, Failed, Stopped }
    property url url
    property int status: LoadRequest.Started
    property string errorString
    property int errorCode: 0
    property string errorDomain
}
