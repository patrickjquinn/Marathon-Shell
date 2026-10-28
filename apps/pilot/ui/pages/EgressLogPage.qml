// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Every remote call Pilot made: when, to whom, why, how much, how long,
// and how it ended. Never what was said. One row per call, newest first,
// in the layout of a Jolla call log: what on the first line with the time
// on the right, the details under it.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Page {
    id: page
    objectName: "egressLogPage"

    property var rows: []
    function reload() { rows = JSON.parse(Pilot.egressLog(500)) }
    Component.onCompleted: reload()

    function purposeText(p) {
        return p === "decide" ? qsTr("Deciding what you asked")
             : p === "chat" ? qsTr("Answer")
             : p === "tool-loop" ? qsTr("Answer, using a tool")
             : p === "token" ? qsTr("Licence check")
             : p === "triage" ? qsTr("Notification sorting")
             : p === "vision" ? qsTr("Camera question")
             : p
    }

    function sizeText(bytes) {
        return bytes >= 1024 ? qsTr("%1 kB").arg((bytes / 1024).toLocaleString(Qt.locale(), "f", 1)) : qsTr("%1 B").arg(bytes)
    }

    SilicaListView {
        id: list
        objectName: "egressList"
        anchors.fill: parent
        model: page.rows
        header: PageHeader {
            title: qsTr("What left this phone")
            description: page.rows.length > 0 ? qsTr("%n request(s)", "", page.rows.length) : ""
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload()
            }
        }

        delegate: ListItem {
            id: row
            required property var modelData
            readonly property bool failed: modelData.result !== "ok"
            contentHeight: Theme.itemSizeMedium

            Label {
                id: purpose
                anchors {
                    left: parent.left; leftMargin: Theme.horizontalPageMargin
                    right: time.left; rightMargin: Theme.paddingMedium
                    bottom: parent.verticalCenter
                }
                truncationMode: TruncationMode.Fade
                color: row.highlighted ? Theme.highlightColor : Theme.primaryColor
                text: page.purposeText(row.modelData.purpose)
            }
            Label {
                id: time
                anchors {
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    baseline: purpose.baseline
                }
                font.pixelSize: Theme.fontSizeExtraSmall
                color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                text: Format.formatDate(new Date(row.modelData.ts_ms), Formatter.TimepointRelative)
            }
            Label {
                anchors {
                    left: purpose.left
                    right: parent.right; rightMargin: Theme.horizontalPageMargin
                    top: parent.verticalCenter
                }
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeExtraSmall
                color: row.failed ? Theme.errorColor
                     : row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                text: row.modelData.provider
                      + " · " + qsTr("%1 out, %2 in").arg(page.sizeText(row.modelData.bytes_out)).arg(page.sizeText(row.modelData.bytes_in))
                      + " · " + qsTr("%1 ms").arg(row.modelData.latency_ms)
                      + (row.failed ? " · " + row.modelData.result : "")
            }
        }

        ViewPlaceholder {
            enabled: page.rows.length === 0
            text: qsTr("Nothing has left this phone")
            hintText: qsTr("Requests to Pilot's servers are listed here as they are made")
        }
        VerticalScrollDecorator {}
    }
}
