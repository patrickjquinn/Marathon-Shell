// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 FilePickerPage, Keel's clean-room version: picks one
// file, browsing folders from the home directory; `nameFilters` (globs such
// as '*.pdf') limit the files shown. Public API and the default title
// ("Select location", as documented) from the Sailfish.Pickers
// documentation.
import QtQuick 2.6
import Sailfish.Pickers 1.0

FileBrowserPage {
    title: qsTr("Select location")
}
