// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The filter lists ads and trackers are blocked with, and when each was
// last updated.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "filterListsPage"

    allowedOrientations: Orientation.All

    SilicaListView {
        anchors.fill: parent
        header: PageHeader {
            title: qsTr("Filter lists")
            description: qsTr("Updated every four days")
        }
        model: PacificList {
            kind: "filterLists"
            revision: Pacific.revision
        }
        PullDownMenu {
            busy: Pacific.listsUpdating
            MenuItem {
                text: Pacific.listsUpdating ? qsTr("Updating") : qsTr("Update now")
                onClicked: if (!Pacific.listsUpdating)
                    Pacific.updateLists(true)
            }
        }
        delegate: TextSwitch {
            required property string itemId
            required property string title
            required property string subtitle
            required property bool on
            required property real time
            required property string detail
            required property real progress
            text: title
            checked: on
            description: subtitle + (detail !== "" ? "\n" + qsTr("Couldn't update. Pacific tries again later.") : (time > 0 ? "\n" + qsTr("%1 rules, checked %2 ago").arg(progress).arg(Logic.ago(time, Date.now())) : ""))
            onClicked: Pacific.setListEnabled(itemId, checked)
        }
        VerticalScrollDecorator {}
    }
}
