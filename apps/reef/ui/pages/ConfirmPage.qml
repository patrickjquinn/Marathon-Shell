// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The confirmation sheet: everything an install, update, Update all or
// removal will do, before it does it (Reef asks before every one; the
// Sailfish forum found it "installs stuff in the background without
// asking"). The list is PackageKit's own simulation of the transaction
// (Reef.pendingPlan, reef-backend's plan.rs), each package labelled as an
// app, an add-on, a library or a background service, with what the
// services do and when they start. Only the button here starts the
// transaction (Reef.confirmPlan()); going back, or Cancel, declines it.
// The window pushes this page on Reef.planReady, also for a Keel Action
// (actions/ReefActions.qml), and brings Reef to the front for it.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components/Texts.js" as Texts

Page {
    id: page
    objectName: "confirmPage"

    // The plan as Reef.pendingPlan gave it (JSON).
    property string planJson
    readonly property var plan: planJson.length > 0 ? JSON.parse(planJson) : ({ items: [] })
    readonly property var items: plan.items || []
    // Set when the person tapped the button, so leaving does not decline.
    property bool answered

    function itemsWhere(test) {
        return page.items.filter(test)
    }
    readonly property var asked: itemsWhere(function(i) { return i.requested })
    readonly property var alsoInstalled: itemsWhere(function(i) { return !i.requested && i.change === "install" })
    readonly property var alsoUpdated: itemsWhere(function(i) {
        return !i.requested && (i.change === "update" || i.change === "reinstall" || i.change === "downgrade")
    })
    readonly property var alsoRemoved: itemsWhere(function(i) { return !i.requested && i.change === "remove" })
    readonly property var kept: itemsWhere(function(i) { return i.change === "keep" })
    // Every background service the plan brings or touches, for the call-out.
    readonly property var services: {
        const out = []
        page.items.forEach(function(i) {
            if (i.change === "keep")
                return
            ;(i.services || []).forEach(function(s) { out.push({ item: i, service: s }) })
        })
        return out
    }
    readonly property var changes: {
        const out = []
        page.items.forEach(function(i) {
            if (i.change === "keep" || i.change === "remove")
                return
            ;(i.system_changes || []).forEach(function(c) { out.push({ item: i, text: c }) })
        })
        return out
    }
    readonly property var outsideSandbox: itemsWhere(function(i) {
        return i.change !== "keep" && i.change !== "remove" && i.sandboxed === false && (i.services || []).length === 0
    })

    function confirm() {
        page.answered = true
        Reef.confirmPlan()
        pageStack.pop()
    }

    // Back, or anything else that takes the page away unanswered: declined.
    onStatusChanged: {
        if (status === PageStatus.Deactivating && !page.answered) {
            page.answered = true
            Reef.declinePlan()
        }
    }

    // One package: its name and what it is, and a line of detail.
    component ItemRow: Item {
        id: row
        required property var modelData
        property bool warn: modelData.stops_working === true
        x: Theme.horizontalPageMargin
        width: (parent ? parent.width : 0) - 2 * Theme.horizontalPageMargin
        height: rowColumn.height + Theme.paddingMedium

        Icon {
            id: rowIcon
            source: row.warn || row.modelData.kind === "background_service"
                    ? "image://theme/icon-s-warning" : "image://theme/icon-s-installed"
            color: row.warn ? Theme.errorColor : Theme.highlightColor
            width: Theme.iconSizeSmall
            height: width
            sourceSize.width: width
            sourceSize.height: height
        }
        Column {
            id: rowColumn
            anchors.left: rowIcon.right
            anchors.leftMargin: Theme.paddingMedium
            anchors.right: parent.right
            Label {
                width: parent.width
                text: row.modelData.title + "  " + row.modelData.version
                color: row.warn ? Theme.errorColor : Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }
            Label {
                width: parent.width
                text: [Texts.kindText(row.modelData.kind),
                       row.modelData.stops_working ? qsTr("stops working without what is removed, so it goes too") : "",
                       row.modelData.reef ? "" : qsTr("from %1").arg(row.modelData.repo),
                       row.modelData.size ? Texts.size(row.modelData.size) : ""]
                      .filter(function(s) { return s.length > 0 }).join(" · ")
                color: row.warn ? Theme.errorColor : Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
            }
        }
    }

    // A list of packages under a heading; hidden when empty.
    component ItemList: Column {
        id: list
        property string title
        property var model: []
        width: parent ? parent.width : 0
        visible: model.length > 0
        SectionHeader { text: list.title }
        Repeater {
            model: list.model
            ItemRow {}
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column
            width: page.width

            PageHeader {
                objectName: "confirmHeader"
                title: Texts.planTitle(page.plan, page.asked)
                description: page.plan.download_size ? qsTr("Download %1").arg(Texts.size(page.plan.download_size)) : ""
            }

            // What removing the app leaves behind, or takes with it, that
            // only the app can deal with (Pilot's voice models, iCloud's
            // accounts): said before the button, as it was in its own
            // dialog before the sheet.
            Label {
                objectName: "removalNote"
                readonly property string note: page.plan.action === "remove" ? Texts.removalNote(page.plan.target) : ""
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: note.length > 0
                wrapMode: Text.Wrap
                color: Theme.highlightColor
                text: note
                bottomPadding: Theme.paddingMedium
            }

            ItemList {
                objectName: "askedList"
                title: page.plan.action === "remove" ? qsTr("Removes")
                     : page.plan.action === "install" ? qsTr("Installs")
                     : qsTr("Updates")
                model: page.asked
            }
            ItemList {
                objectName: "alsoInstalls"
                title: qsTr("Also installs")
                model: page.alsoInstalled
            }
            ItemList {
                objectName: "alsoUpdates"
                title: qsTr("Also updates")
                model: page.alsoUpdated
            }
            ItemList {
                objectName: "alsoRemoves"
                title: qsTr("Also removes")
                model: page.alsoRemoved
            }

            // What runs by itself: each service, what it does, when it
            // starts. In the warning colour: the forum asked to be told.
            SectionHeader {
                text: qsTr("Runs in the background")
                visible: page.services.length > 0 || page.outsideSandbox.length > 0
            }
            Repeater {
                model: page.services
                Label {
                    id: serviceLabel
                    required property var modelData
                    objectName: "service"
                    x: Theme.horizontalPageMargin
                    width: page.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    bottomPadding: Theme.paddingSmall
                    text: qsTr("%1 (%2): %3").arg(serviceLabel.modelData.item.title)
                              .arg(Texts.startsText(serviceLabel.modelData.service.starts))
                              .arg(serviceLabel.modelData.service.description || serviceLabel.modelData.service.name)
                }
            }
            Repeater {
                model: page.outsideSandbox
                Label {
                    required property var modelData
                    x: Theme.horizontalPageMargin
                    width: page.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    bottomPadding: Theme.paddingSmall
                    text: qsTr("%1 runs outside the Sailfish OS sandbox, with your access to files and data.").arg(modelData.title)
                }
            }

            SectionHeader {
                text: qsTr("Changes to your phone")
                visible: page.changes.length > 0
            }
            Repeater {
                model: page.changes
                Label {
                    id: changeLabel
                    required property var modelData
                    objectName: "systemChange"
                    x: Theme.horizontalPageMargin
                    width: page.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    bottomPadding: Theme.paddingSmall
                    text: qsTr("%1: %2").arg(changeLabel.modelData.item.title).arg(changeLabel.modelData.text)
                }
            }

            // A removal leaves these: only the app needed them, but Reef
            // has no record of installing them.
            ItemList {
                objectName: "kept"
                title: qsTr("Stays installed")
                model: page.kept
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.kept.length > 0
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: qsTr("Reef has no record of installing these, so it leaves them in place.")
            }

            Item { width: 1; height: Theme.paddingLarge }
            Button {
                objectName: "confirmButton"
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthLarge
                text: page.plan.action === "remove" ? qsTr("Remove")
                    : page.plan.action === "install" ? qsTr("Install")
                    : qsTr("Update")
                onClicked: page.confirm()
            }
            Item { width: 1; height: Theme.paddingMedium }
            Button {
                objectName: "cancelButton"
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthLarge
                backgroundColor: "transparent"
                text: qsTr("Cancel")
                onClicked: pageStack.pop()
            }
        }

        VerticalScrollDecorator {}
    }
}
