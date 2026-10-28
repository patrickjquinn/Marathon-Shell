// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One app: what it is, what is new in it, what it may access, and
// install, open, update, remove or buy.
// Laid out as the Jolla Store lays out an
// app (the name and publisher right-aligned beside the icon), then the one
// thing to do, the facts at a glance, the screenshots, and the rest in
// sections. Everything shown comes from the developer's catalogue entry:
// it is plain text (the window's default label format), and only https://
// links are ever opened.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components"
import "../components/Texts.js" as Texts

Page {
    id: page

    property string packageName
    // Re-read whenever the models are rebuilt (a refresh, an operation, a
    // licence change): reading Reef.revision makes the binding depend on it.
    readonly property var pkg: {
        const revision = Reef.revision
        return revision >= 0 ? Reef.packageDetails(packageName) : ({})
    }
    readonly property var changes: Texts.changelog(pkg.changelogJson)
    // What it brings that runs by itself, and what it changes on the phone
    // (the catalogue's disclosures, over everything it pulls in).
    readonly property var services: pkg.servicesJson ? JSON.parse(pkg.servicesJson) : []
    readonly property var systemChanges: pkg.systemChangesJson ? JSON.parse(pkg.systemChangesJson) : []
    readonly property bool paid: pkg.licenceModel === "one_off" || pkg.licenceModel === "subscription"
    // Why the last purchase could not start.
    property string error

    // From the store index the details (description, screenshots, what is
    // new, what it brings) come when the page opens; Reef.revision brings
    // them into `pkg`.
    Component.onCompleted: Reef.loadDetails(packageName)

    readonly property bool installed: pkg.installState !== undefined && pkg.installState !== "not_installed"
    readonly property bool updatable: pkg.installState === "update_available"
    // The row carries the store handler's progress on this app.
    readonly property var row: (Reef.revision, Reef.appRow(packageName))
    readonly property string job: row.jobState || ""
    readonly property bool working: job === "pending" || job === "installing" || job === "removing" || job === "cancelling"
    readonly property bool canBuy: paid && !pkg.licensed && Texts.isHttps(pkg.purchaseUrl)
    // Set once Buy has opened the checkout in the browser.
    property bool buying

    // Opens the checkout with a new claim code in its URL; Reef fetches
    // the licence with that code once the purchase is paid.
    function buy() {
        const url = Reef.buyUrl(page.packageName)
        if (url.length === 0) {
            page.error = Texts.message(Reef.lastError)
            return
        }
        page.error = ""
        page.buying = true
        Texts.openHttps(url)
    }

    // A changelog entry: its version and day, then its notes as a list.
    component ChangeEntry: Column {
        id: entry
        required property var change
        width: parent ? parent.width : 0
        spacing: Theme.paddingSmall

        Item {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            height: versionLabel.height
            Label {
                id: versionLabel
                anchors.left: parent.left
                anchors.right: dateLabel.left
                anchors.rightMargin: Theme.paddingMedium
                text: entry.change.version ? qsTr("Version %1").arg(entry.change.version) : ""
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                truncationMode: TruncationMode.Fade
            }
            Label {
                id: dateLabel
                anchors.right: parent.right
                anchors.baseline: versionLabel.baseline
                text: Texts.date(entry.change.date)
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
            }
        }
        Repeater {
            model: entry.change.notes || []
            // A bullet with a hanging indent.
            Item {
                id: note
                required property string modelData
                x: Theme.horizontalPageMargin
                width: entry.width - 2 * Theme.horizontalPageMargin
                height: noteText.height
                Label {
                    id: bullet
                    text: "•"
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
                Label {
                    id: noteText
                    anchors.left: bullet.right
                    anchors.leftMargin: Theme.paddingMedium
                    anchors.right: parent.right
                    text: note.modelData
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }
    }

    // One fact in the row under the button: the value over its name.
    component Fact: Column {
        id: fact
        required property string value
        required property string name
        width: facts.width / 3
        spacing: Theme.paddingSmall / 2
        Label {
            width: parent.width
            // Centred while it fits; too long, it starts at the left and fades out.
            horizontalAlignment: implicitWidth > width ? Text.AlignLeft : Text.AlignHCenter
            text: fact.value
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeMedium
            truncationMode: TruncationMode.Fade
        }
        Label {
            width: parent.width
            // Centred while it fits; too long, it starts at the left and fades out.
            horizontalAlignment: implicitWidth > width ? Text.AlignLeft : Text.AlignHCenter
            text: fact.name
            color: Theme.secondaryHighlightColor
            font.pixelSize: Theme.fontSizeExtraSmall
            truncationMode: TruncationMode.Fade
        }
    }

    // A line with a small icon in front: permissions, compatibility.
    component IconLine: Item {
        id: line
        property string source
        property string text
        // Static text, so the highlight colour (Silica keeps the primary
        // colour for what can be tapped).
        property color color: Theme.highlightColor
        x: Theme.horizontalPageMargin
        width: (parent ? parent.width : 0) - 2 * Theme.horizontalPageMargin
        height: Math.max(lineIcon.height, lineText.height) + Theme.paddingSmall
        Icon {
            id: lineIcon
            anchors.verticalCenter: lineText.lineCount > 1 ? undefined : parent.verticalCenter
            source: line.source
            width: Theme.iconSizeSmallPlus
            height: width
            sourceSize.width: width
            sourceSize.height: height
            color: line.color
        }
        Label {
            id: lineText
            anchors.left: lineIcon.right
            anchors.leftMargin: Theme.paddingMedium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: line.text
            wrapMode: Text.Wrap
            color: line.color
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // A link to the developer's pages, as a list row.
    component LinkItem: BackgroundItem {
        id: link
        property string iconSource
        property string text
        property string url
        visible: Texts.isHttps(url)
        // Sized by its own condition, not `visible`: `visible` is also false while the page is hidden under another, and a height that followed it collapsed the page's content then (its scroll position was lost on the way back).
        height: (Texts.isHttps(url)) ? Theme.itemSizeSmall : 0
        onClicked: Texts.openHttps(url)
        Icon {
            id: linkIcon
            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: link.iconSource
            color: link.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            anchors.left: linkIcon.right
            anchors.leftMargin: Theme.paddingLarge
            anchors.right: arrow.left
            anchors.verticalCenter: parent.verticalCenter
            text: link.text
            color: link.highlighted ? Theme.highlightColor : Theme.primaryColor
            truncationMode: TruncationMode.Fade
        }
        Icon {
            id: arrow
            anchors.right: parent.right
            anchors.rightMargin: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: "image://theme/icon-m-right"
            color: link.highlighted ? Theme.highlightColor : Theme.secondaryColor
        }
    }

    SilicaFlickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge * 2

        // Removing it, and the links to the developer's pages.
        PullDownMenu {
            visible: removeItem.visible || Texts.isHttps(page.pkg.source) || Texts.isHttps(page.pkg.homepage)
            MenuItem {
                id: removeItem
                objectName: "removeItem"
                text: qsTr("Remove")
                visible: page.installed && !page.working && page.pkg.installable === true
                onClicked: remorse.execute(qsTr("Removing"), function() { Reef.uninstall(page.packageName) })
            }
            MenuItem {
                objectName: "sourceItem"
                text: qsTr("Source code")
                visible: Texts.isHttps(page.pkg.source)
                onClicked: Texts.openHttps(page.pkg.source)
            }
            MenuItem {
                objectName: "homepageItem"
                text: qsTr("Website")
                visible: Texts.isHttps(page.pkg.homepage)
                onClicked: Texts.openHttps(page.pkg.homepage)
            }
        }

        RemorsePopup { id: remorse }

        Column {
            id: column
            width: page.width

            // The name and who publishes it, right-aligned beside the icon,
            // below the camera cut-out (as PageHeader keeps clear of it): the
            // heading is centred on the icon while it fits and grows down,
            // never up, when a larger text size makes it taller.
            Item {
                id: headingRow
                objectName: "headingRow"
                readonly property real headingTop: Math.max(Theme.paddingLarge * 2,
                                                     (page.isPortrait ? Screen.topCutout.height : 0) + Theme.paddingMedium)
                width: parent.width
                height: Math.max(appIcon.y + appIcon.height, heading.y + heading.height) + Theme.paddingLarge

                AppIcon {
                    id: appIcon
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    y: headingRow.headingTop
                    iconPath: page.pkg.iconPath || ""
                    title: page.pkg.title || ""
                    size: Theme.iconSizeExtraLarge
                }

                Column {
                    id: heading
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.right: appIcon.left
                    anchors.rightMargin: Theme.paddingLarge
                    y: Math.max(headingRow.headingTop, appIcon.y + (appIcon.height - height) / 2)

                    Label {
                        objectName: "title"
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: page.pkg.title || ""
                        color: Theme.highlightColor
                        font.pixelSize: Theme.fontSizeExtraLarge
                        font.family: Theme.fontFamilyHeading
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    Label {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        visible: !!page.pkg.summary
                        text: page.pkg.summary || ""
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Label {
                        objectName: "publisher"
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        topPadding: Theme.paddingSmall
                        text: [page.pkg.publisher || "", page.pkg.category || ""]
                              .filter(function(s) { return s.length > 0 }).join(" · ")
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            // The one thing to do with this app: install, update, or buy.
            // Paid packages install freely (the app checks its own licence
            // offline); buying happens on the web, through the merchant of
            // record. One action at a time: install first, then buy.
            Item {
                id: actions
                objectName: "actions"
                readonly property bool buyNow: page.canBuy && page.pkg.installState === "installed"
                width: parent.width
                visible: page.pkg.installable === true || page.canBuy
                height: visible ? (page.working ? progress.height : actionRow.height) + Theme.paddingMedium : 0

                Row {
                    id: actionRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.paddingLarge
                    visible: !page.working
                    // Buttons share the width; one alone takes the large size.
                    readonly property int shown: (installButton.visible ? 1 : 0) + (openButton.visible ? 1 : 0)
                        + (updateButton.visible ? 1 : 0) + (buyButton.visible ? 1 : 0)
                    readonly property real buttonWidth: shown > 1
                        ? (page.width - 2 * Theme.horizontalPageMargin - (shown - 1) * spacing) / shown
                        : Theme.buttonWidthLarge

                    Button {
                        id: installButton
                        objectName: "installButton"
                        visible: !page.installed && page.pkg.installable === true
                        preferredWidth: actionRow.buttonWidth
                        text: qsTr("Install")
                        onClicked: Reef.install(page.packageName)
                    }
                    Button {
                        id: openButton
                        objectName: "openButton"
                        visible: page.installed
                        preferredWidth: actionRow.buttonWidth
                        text: qsTr("Open")
                        onClicked: Reef.open(page.packageName)
                    }
                    Button {
                        id: updateButton
                        objectName: "updateButton"
                        visible: page.updatable
                        preferredWidth: actionRow.buttonWidth
                        text: qsTr("Update")
                        onClicked: Reef.update(page.packageName)
                    }
                    Button {
                        id: buyButton
                        objectName: "buyButton"
                        visible: actions.buyNow
                        preferredWidth: actionRow.buttonWidth
                        text: page.pkg.licenceModel === "subscription" ? qsTr("Subscribe") : qsTr("Buy")
                        onClicked: page.buy()
                    }
                }

                // While the store handler works on it: how far, and a way out
                // before it is installed.
                Item {
                    id: progress
                    objectName: "progress"
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Math.max(bar.height, cancelButton.height)
                    visible: page.working

                    ProgressBar {
                        id: bar
                        anchors.left: parent.left
                        anchors.right: cancelButton.visible ? cancelButton.left : parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        indeterminate: (page.row.jobPercent || -1) < 0
                        minimumValue: 0
                        maximumValue: 100
                        value: Math.max(0, page.row.jobPercent || 0)
                        label: page.job === "removing" ? qsTr("Removing")
                             : page.job === "cancelling" ? qsTr("Stopping")
                             : page.job === "pending" ? qsTr("Waiting")
                             : qsTr("Installing")
                    }
                    Button {
                        id: cancelButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.job === "pending" || page.job === "installing"
                        text: qsTr("Cancel")
                        onClicked: Reef.cancel(page.packageName)
                    }
                }
            }

            // Why the last install, update or removal did not happen.
            Label {
                objectName: "jobError"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.job === "failed"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: page.row.jobError ? qsTr("Couldn't finish: %1").arg(page.row.jobError) : qsTr("Couldn't finish.")
                bottomPadding: Theme.paddingMedium
            }

            // An app Marathon has no way to install (a Sailfish package).
            Label {
                objectName: "notInstallable"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !page.installed && page.pkg.installable === false
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: qsTr("This app can't be installed on Marathon.")
                bottomPadding: Theme.paddingMedium
            }

            // The versions an update moves between, or that it is installed
            // and current.
            Label {
                objectName: "installedNote"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.installed
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                // Full strength only when there is something to do: the
                // button above already says the app is installed.
                color: page.updatable ? Theme.highlightColor : Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                text: page.updatable
                      ? qsTr("%1 installed, %2 available").arg(page.pkg.installedVersion).arg(page.pkg.updateVersion || page.pkg.version)
                      : qsTr("Up to date · %1").arg(page.pkg.installedVersion)
                bottomPadding: Theme.paddingMedium
            }

            // After Buy: the licence arrives by itself once paid.
            Label {
                objectName: "buyHint"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.buying && page.canBuy
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("Finish the purchase in the browser. Reef adds the licence when you come back.")
                bottomPadding: Theme.paddingMedium
            }

            Label {
                objectName: "operationError"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.error.length > 0
                wrapMode: Text.Wrap
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                text: qsTr("That didn't work: %1").arg(page.error)
                bottomPadding: Theme.paddingMedium
            }

            // The facts at a glance.
            Row {
                id: facts
                objectName: "facts"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                topPadding: Theme.paddingLarge
                bottomPadding: Theme.paddingLarge

                Fact { value: Texts.price(page.pkg.licenceModel, page.pkg.licensed); name: qsTr("Price") }
                Fact { value: page.pkg.sizeText || "–"; name: qsTr("Installed size") }
                Fact {
                    value: Texts.date(page.pkg.updated) || "–"
                    name: page.changes.length > 0 ? qsTr("Updated") : qsTr("Published")
                }
            }

            // Screenshots the repository ships (cached files, like the
            // icon), at the phone's proportions, two and a bit across so
            // it shows there are more; one alone is the same size, centred
            // (at half the page wide it took half the screen). A tap opens
            // them full screen.
            Flickable {
                id: shotStrip
                objectName: "screenshots"
                readonly property real shotWidth:
                    Math.round((page.width - Theme.horizontalPageMargin - 2 * Theme.paddingMedium) / 2.5)
                width: parent.width
                height: (shots.count > 0) ? Math.round(shotWidth * 2.1) + Theme.paddingLarge : 0
                visible: shots.count > 0
                contentWidth: Math.max(width, shotRow.width)
                flickableDirection: Flickable.HorizontalFlick
                clip: true

                Row {
                    id: shotRow
                    x: shots.count === 1 ? Math.round((shotStrip.width - width) / 2) : 0
                    height: shotStrip.height - Theme.paddingLarge
                    spacing: Theme.paddingMedium

                    Item { width: Theme.horizontalPageMargin - shotRow.spacing; height: 1; visible: shots.count > 1 }
                    Repeater {
                        id: shots
                        model: page.pkg.screenshotPaths || []
                        BackgroundItem {
                            id: shot
                            required property string modelData
                            required property int index
                            objectName: "screenshot" + index
                            height: parent.height
                            width: shotStrip.shotWidth
                            onClicked: pageStack.push(Qt.resolvedUrl("ScreenshotPage.qml"), {
                                paths: page.pkg.screenshotPaths,
                                startIndex: shot.index
                            })

                            Image {
                                anchors.fill: parent
                                source: "file://" + shot.modelData
                                sourceSize.width: width
                                fillMode: Image.PreserveAspectCrop
                                verticalAlignment: Image.AlignTop
                                asynchronous: true
                                smooth: true
                            }
                        }
                    }
                    Item { width: Theme.horizontalPageMargin - shotRow.spacing; height: 1; visible: shots.count > 1 }
                }

                HorizontalScrollDecorator {}
            }

            // Everything below the screenshots, built once the page has
            // slid in, a little at a time: built with the rest, it held
            // the push back (the page appeared some 150 ms after the tap,
            // then slid). What shows first is all above this.
            Loader {
                id: details
                objectName: "detailsLoader"
                width: parent.width
                active: page.status === PageStatus.Active || item !== null
                asynchronous: true
                sourceComponent: Column {
                    width: details.width

                    // The description, five lines until asked for more.
                    SectionHeader { text: qsTr("About"); visible: !!page.pkg.description }
                    Label {
                        id: description
                        property bool expanded
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        visible: !!page.pkg.description
                        wrapMode: Text.Wrap
                        maximumLineCount: expanded ? 1000 : 5
                        elide: Text.ElideRight
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.highlightColor
                        text: page.pkg.description || ""
                    }
                    BackgroundItem {
                        objectName: "moreButton"
                        width: parent.width
                        height: (!!page.pkg.description && (description.truncated || description.expanded)) ? Theme.itemSizeExtraSmall : 0
                        visible: description.visible && (description.truncated || description.expanded)
                        onClicked: description.expanded = !description.expanded
                        Label {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: description.expanded ? qsTr("Show less") : qsTr("Show more")
                            color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    // What changed in the newest version; the earlier ones folded
                    // away under "Version history".
                    SectionHeader { text: qsTr("What's new"); visible: page.changes.length > 0 }
                    ChangeEntry {
                        objectName: "whatsNew"
                        visible: page.changes.length > 0
                        change: page.changes.length > 0 ? page.changes[0] : ({})
                    }
                    Item { width: 1; height: Theme.paddingMedium; visible: page.changes.length > 1 }
                    ExpandingSection {
                        objectName: "versionHistory"
                        width: parent.width
                        visible: page.changes.length > 1
                        title: qsTr("Version history")
                        content.sourceComponent: Column {
                            width: parent ? parent.width : page.width
                            spacing: Theme.paddingLarge
                            bottomPadding: Theme.paddingMedium
                            Repeater {
                                model: page.changes.slice(1)
                                ChangeEntry {
                                    required property var modelData
                                    change: modelData
                                }
                            }
                        }
                    }

                    // What it brings that runs by itself, and what it changes on
                    // the phone beyond its own files, from the RPMs (gen-catalogue):
                    // in the warning style, before install.
                    SectionHeader {
                        text: qsTr("Runs in the background")
                        visible: page.services.length > 0
                    }
                    Column {
                        width: parent.width
                        spacing: Theme.paddingSmall
                        Repeater {
                            model: page.services
                            IconLine {
                                required property var modelData
                                objectName: "serviceLine"
                                source: "image://theme/icon-s-warning"
                                text: qsTr("%1 (%2)").arg(modelData.description || modelData.name)
                                                     .arg(Texts.startsText(modelData.starts))
                            }
                        }
                    }
                    SectionHeader {
                        text: qsTr("Changes to your phone")
                        visible: page.systemChanges.length > 0
                    }
                    // Lines that share a head (each package's install scripts)
                    // under it once, what each does indented below; a gap between
                    // separate lines.
                    Column {
                        width: parent.width
                        spacing: Theme.paddingSmall
                        Repeater {
                            model: Texts.groupLines(page.systemChanges.map(function(c) { return c.description }))
                            Column {
                                id: changeGroup
                                required property var modelData
                                width: parent.width
                                IconLine {
                                    objectName: "systemChangeLine"
                                    source: "image://theme/icon-s-warning"
                                    text: changeGroup.modelData.items.length > 0
                                          ? qsTr("%1:").arg(changeGroup.modelData.text) : changeGroup.modelData.text
                                }
                                Repeater {
                                    model: changeGroup.modelData.items
                                    // A bullet with its lines hanging after it.
                                    Item {
                                        id: changeItem
                                        required property string modelData
                                        x: Theme.horizontalPageMargin + Theme.iconSizeSmallPlus + Theme.paddingMedium
                                        width: parent.width - x - Theme.horizontalPageMargin
                                        height: itemText.height + Theme.paddingSmall
                                        Label {
                                            id: bullet
                                            text: "•"
                                            color: Theme.secondaryHighlightColor
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                        Label {
                                            id: itemText
                                            objectName: "systemChangeItem"
                                            x: bullet.width + Theme.paddingSmall
                                            width: parent.width - x
                                            text: changeItem.modelData
                                            wrapMode: Text.Wrap
                                            color: Theme.highlightColor
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // What it may reach on the phone, from the app's own desktop
                    // file: before install, in words.
                    SectionHeader { text: qsTr("Permissions") }
                    Column {
                        id: permissionList
                        objectName: "permissions"
                        // The first few, the rest a tap away: twenty lines of
                        // permissions buried the rest of the page.
                        readonly property var all: page.pkg.permissions || []
                        readonly property int firstFew: 5
                        property bool showAll
                        width: parent.width
                        spacing: Theme.paddingSmall

                        IconLine {
                            source: page.pkg.sandboxed === false ? "image://theme/icon-s-warning" : "image://theme/icon-s-secure"
                            text: page.pkg.sandboxed === false
                                  ? qsTr("Parts of it run outside the app sandbox, with your access to files and data.")
                                  : (page.pkg.permissions || []).length > 0
                                    ? qsTr("Runs in the app sandbox, and may use:")
                                    : qsTr("Runs in the app sandbox, and asks for no extra permissions.")
                            color: page.pkg.sandboxed === false ? Theme.highlightColor : Theme.secondaryHighlightColor
                        }
                        Repeater {
                            model: permissionList.showAll ? permissionList.all
                                                          : permissionList.all.slice(0, permissionList.firstFew)
                            IconLine {
                                required property string modelData
                                source: Texts.permission(modelData).icon
                                text: Texts.permission(modelData).label
                            }
                        }
                    }
                    BackgroundItem {
                        id: morePermissions
                        objectName: "morePermissions"
                        width: parent.width
                        height: permissionList.all.length > permissionList.firstFew ? Theme.itemSizeExtraSmall : 0
                        visible: permissionList.all.length > permissionList.firstFew
                        onClicked: permissionList.showAll = !permissionList.showAll
                        Label {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            text: permissionList.showAll ? qsTr("Show fewer")
                                                         : qsTr("Show all %n permission(s)", "", permissionList.all.length)
                            color: morePermissions.highlighted ? Theme.highlightColor : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }

                    SectionHeader { text: qsTr("Information") }
                    DetailItem { label: qsTr("Version"); value: page.pkg.version || "" }
                    DetailItem {
                        label: qsTr("Installed")
                        value: page.pkg.installedVersion || ""
                        // Only when it is not the version above (an update waits).
                        visible: page.installed && page.pkg.installedVersion !== page.pkg.version
                    }
                    DetailItem { label: qsTr("Publisher"); value: page.pkg.publisher || ""; visible: !!page.pkg.publisher }
                    DetailItem { label: qsTr("Licence"); value: Texts.licence(page.pkg.spdx); visible: !!page.pkg.spdx }
                    DetailItem {
                        label: qsTr("First published")
                        value: Texts.date(page.pkg.added)
                        visible: !!page.pkg.added && page.changes.length > 0
                    }
                    DetailItem {
                        // The catalogue's keel_tier, the tier keel-compat measures
                        // (docs/plan.md, "Compatibility target", where B is the
                        // higher): how much of the app runs on Keel, Sailfish's Qt 6.
                        label: qsTr("Qt 6 (Keel)")
                        value: page.pkg.keelTier === "B" ? qsTr("Fully supported")
                             : page.pkg.keelTier === "A" ? qsTr("Mostly supported")
                             : page.pkg.keelTier === "none" ? qsTr("Not supported yet")
                             : page.pkg.keelTier === "not-applicable" ? qsTr("Not needed")
                             : (page.pkg.keelTier || "")
                        visible: !!page.pkg.keelTier
                    }

                    Item { width: 1; height: Theme.paddingLarge }
                    LinkItem {
                        objectName: "homepageLink"
                        iconSource: "image://theme/icon-m-website"
                        text: qsTr("Website")
                        url: page.pkg.homepage || ""
                    }
                    LinkItem {
                        objectName: "sourceLink"
                        iconSource: "image://theme/icon-m-developer-mode"
                        text: qsTr("Source code")
                        url: page.pkg.source || ""
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
