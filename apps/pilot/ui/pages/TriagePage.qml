// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Proactive triage results (spec section 5.3), inside the app: what to act
// on now first, then today, later and what was set aside, each under its
// section header as in Jolla's notification lists. On a phone the summary
// also shows in Lipstick's Events view (../../lipstick/eventswidget).

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pilot 1.0

Page {
    id: page
    objectName: "triagePage"

    property var items: []
    readonly property var bucketOrder: ["act_now", "today", "later", "ignore"]

    ListModel { id: sorted }

    function reload() {
        items = JSON.parse(Pilot.triage())
        var rows = items.slice(0)
        rows.sort(function(a, b) {
            var d = page.rank(a.bucket) - page.rank(b.bucket)
            return d !== 0 ? d : (b.ts_ms || 0) - (a.ts_ms || 0)
        })
        sorted.clear()
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i]
            sorted.append({ section: page.bucketText(r.bucket), title: r.title || "", body: r.body || "",
                            source: r.app || r.source || "", ts: r.ts_ms || 0, urgent: (r.urgency || 0) >= 1.5 })
        }
    }
    Component.onCompleted: reload()

    function rank(b) {
        var i = bucketOrder.indexOf(b)
        return i < 0 ? bucketOrder.length : i
    }

    function bucketText(b) {
        return b === "act_now" ? qsTr("Now")
             : b === "today" ? qsTr("Today")
             : b === "later" ? qsTr("Later")
             : qsTr("Set aside")
    }

    SilicaListView {
        objectName: "triageList"
        anchors.fill: parent
        model: sorted
        header: PageHeader { title: qsTr("Pilot events") }
        section.property: "section"
        section.delegate: SectionHeader {
            required property string section
            text: section
        }

        PullDownMenu {
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: page.reload()
            }
        }

        delegate: ListItem {
            id: row
            required property string title
            required property string body
            required property string source
            required property real ts
            required property bool urgent
            contentHeight: col.height + 2 * Theme.paddingMedium

            Column {
                id: col
                x: Theme.horizontalPageMargin
                y: Theme.paddingMedium
                width: parent.width - 2 * Theme.horizontalPageMargin

                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    color: row.highlighted || row.urgent ? Theme.highlightColor : Theme.primaryColor
                    text: row.title
                }
                Label {
                    visible: text.length > 0
                    width: parent.width
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    text: row.body
                }
                Label {
                    width: parent.width
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: row.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    text: (row.source.length > 0 ? row.source + " · " : "")
                          + (row.ts > 0 ? Format.formatDate(new Date(row.ts), Formatter.TimepointRelative) : "")
                }
            }
        }

        ViewPlaceholder {
            enabled: sorted.count === 0
            text: qsTr("No events")
            hintText: qsTr("Pull down to open Settings and turn on notification sorting")
        }
        VerticalScrollDecorator {}
    }
}
