// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 ImagePickerPage, Keel's clean-room version: picks
// an image file. Public API (selectedContent, selectedContentProperties, title)
// and the default title from the Sailfish.Pickers documentation; the page
// itself is Keel's (PROVENANCE.md).
import QtQuick 2.6
import Sailfish.Pickers 1.0

ContentPickerPageBase {
    title: qsTr("Select image")
    _contentType: KeelContentModel.ImageContent
}
