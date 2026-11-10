// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// QuickScrollButtonBase (Sailfish.Silica.private): the pressable base of
// Silica's BSD private/QuickScrollButton.qml (`flickable`, MouseArea
// signals). Keel's stand-in.
import QtQuick
import Sailfish.Silica.private 1.0

SilicaMouseArea {
    property Item flickable
}
