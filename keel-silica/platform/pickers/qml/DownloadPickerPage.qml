// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 DownloadPickerPage, Keel's clean-room version: picks
// a file from the downloads directory. Public API (selectedContent,
// selectedContentProperties, title) and the default title ("Select
// document", as documented) from the Sailfish.Pickers documentation; the
// page itself is Keel's (PROVENANCE.md).
import QtQuick 2.6
import Sailfish.Pickers 1.0

ContentPickerPageBase {
    title: qsTr("Select document")
    _contentType: KeelContentModel.DownloadContent
}
