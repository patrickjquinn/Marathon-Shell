// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Pickers 1.0 MultiDocumentPickerDialog, Keel's clean-room version:
// selects several document files. Public API (acceptText, selectedContent, title)
// from the Sailfish.Pickers documentation; the dialog itself is Keel's.
import QtQuick 2.6
import Sailfish.Pickers 1.0

MultiContentPickerDialogBase {
    _contentType: KeelContentModel.DocumentContent
}
