// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
import QtQuick 2.6

QtObject {
    property string storageName
    readonly property bool offTheRecord: storageName.length === 0
    property string httpUserAgent: "FakeEngine/1.0"
    property string downloadPath
    signal downloadRequested(var download)
    Component.onCompleted: FakeLog.profiles.push(this)
}
