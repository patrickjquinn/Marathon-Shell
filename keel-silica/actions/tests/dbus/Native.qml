// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The QML of the Rust test app: only the import, which loads the
// Keel.Actions runtime; every action is native.
import QtQuick 2.15
import Keel.Actions 1.0

Item {
    readonly property string app: KeelActions.appId
}
