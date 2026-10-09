// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sample app in the style of Harbour apps (SDK template layout), used by
// tst_compat_app.qml. Written for Keel; no third-party code.
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    objectName: "detailPage"
    property string note

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium
            PageHeader { title: note }
            DetailItem { label: qsTr("Length"); value: note.length }
            Separator { width: parent.width; color: Theme.primaryColor; horizontalAlignment: Qt.AlignHCenter }
            BusyIndicator { anchors.horizontalCenter: parent.horizontalCenter; running: false; size: BusyIndicatorSize.Medium }
        }
    }
}
