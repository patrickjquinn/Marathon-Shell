pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// One app: header, key facts, screenshots, what's new, description,
// ratings and reviews, permissions, information.
Page {
    id: root

    property var store
    property string appId
    // The list entry the user tapped, shown until the full record lands.
    property var summaryApp: null
    property var fullApp: null
    property var summary: null
    property var reviews: []
    property bool descriptionExpanded: false
    property bool detailsLoading: true
    property bool detailsFailed: false

    readonly property var app: fullApp || summaryApp || ({})
    readonly property var rating: store.ratingFor(appId)
    readonly property var screenshots: app.screenshots || []
    readonly property var latestRelease: (app.releases && app.releases.length > 0) ? app.releases[0] : null
    readonly property var permissions: summary && summary.metadata ? store.describePermissions(summary.metadata.permissions) : []
    readonly property bool installed: store.isInstalled(appId)
    readonly property var job: store.jobFor(appId)
    readonly property string homepage: app.urls && app.urls.homepage ? app.urls.homepage : ""
    readonly property string bugtracker: app.urls && app.urls.bugtracker ? app.urls.bugtracker : ""
    readonly property var sensitivePermissions: permissions.filter(p => p.risky)
    readonly property var otherPermissions: permissions.filter(p => !p.risky)

    function uninstall() {
        remorse.execute(qsTr("Uninstalled %1").arg(app.name || appId), function () {
            root.store.uninstallApp(root.appId);
        });
    }

    function load() {
        detailsLoading = true;
        detailsFailed = false;
        let waiting = 2;
        const settle = ok => {
            if (!ok)
                root.detailsFailed = true;
            if (--waiting === 0)
                root.detailsLoading = false;
        };
        store.loadAppstream(appId, function (full) {
            if (full)
                root.fullApp = full;
            settle(full !== null);
        });
        store.loadSummary(appId, function (s) {
            if (s)
                root.summary = s;
            settle(s !== null);
        });
        store.loadReviews(appId, function (list) {
            root.reviews = list;
        });
    }

    Component.onCompleted: {
        store.ensureRating(appId);
        load();
    }

    RemorsePopup {
        id: remorse
    }

    Component {
        id: permissionRow

        Item {
            id: perm

            required property var modelData

            x: Theme.horizontalPageMargin
            width: root.width - 2 * Theme.horizontalPageMargin
            height: Math.max(permIcon.height, permText.height)
            Accessible.role: Accessible.StaticText
            Accessible.name: modelData.label + ": " + modelData.detail

            Icon {
                id: permIcon
                anchors.verticalCenter: parent.verticalCenter
                source: "image://theme/icon-m-" + perm.modelData.icon
                color: perm.modelData.risky ? Theme.errorColor : Theme.highlightColor
            }
            Column {
                id: permText
                anchors.left: permIcon.right
                anchors.leftMargin: Theme.paddingMedium
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Label {
                    width: parent.width
                    text: perm.modelData.label
                    color: Theme.highlightColor
                }
                Label {
                    width: parent.width
                    text: perm.modelData.detail
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    SilicaFlickable {
        id: flick

        objectName: "detailView"
        anchors.fill: parent
        contentHeight: body.height + Theme.paddingLarge

        PullDownMenu {
            visible: root.installed || root.detailsFailed || root.homepage !== "" || root.bugtracker !== ""
            MenuItem {
                objectName: "uninstallItem"
                text: qsTr("Uninstall")
                visible: root.installed
                onClicked: root.uninstall()
            }
            MenuItem {
                objectName: "reportItem"
                text: qsTr("Report a problem")
                visible: root.bugtracker !== ""
                onClicked: root.store.openExternally(root.bugtracker)
            }
            MenuItem {
                objectName: "websiteItem"
                text: qsTr("Visit website")
                visible: root.homepage !== ""
                onClicked: root.store.openExternally(root.homepage)
            }
            MenuItem {
                objectName: "retryItem"
                text: qsTr("Try again")
                visible: root.detailsFailed
                onClicked: root.load()
            }
        }

        Column {
            id: body

            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                title: root.app.name || root.appId
            }

            // ── Header ────────────────────────────────────
            Item {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Math.max(bigIcon.height, headerText.height)

                AppIcon {
                    id: bigIcon
                    width: Theme.iconSizeExtraLarge
                    height: width
                    source: root.store.iconFor(root.app)
                }
                Column {
                    id: headerText
                    anchors.left: bigIcon.right
                    anchors.leftMargin: Theme.paddingLarge
                    anchors.right: parent.right
                    anchors.verticalCenter: bigIcon.verticalCenter
                    spacing: Theme.paddingSmall

                    Row {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Label {
                            id: developer
                            width: Math.min(implicitWidth, parent.width - (verified.visible ? verified.width + parent.spacing : 0))
                            text: root.app.developer_name || ""
                            color: Theme.highlightColor
                            truncationMode: TruncationMode.Fade
                        }
                        Icon {
                            id: verified
                            anchors.verticalCenter: developer.verticalCenter
                            width: Theme.iconSizeSmall
                            height: width
                            visible: root.store.isVerified(root.app)
                            source: "image://theme/icon-s-verified"
                            color: Theme.highlightColor
                            Accessible.role: Accessible.Graphic
                            Accessible.name: qsTr("Verified developer")
                        }
                    }
                    Label {
                        width: parent.width
                        text: root.store.categoryLabel(root.app) || ""
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                    }
                    StarRating {
                        visible: root.rating !== null
                        value: root.rating ? root.rating.average : 0
                        color: Theme.highlightColor
                    }
                }
            }

            GetButton {
                objectName: "detailAction"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                store: root.store
                appId: root.appId
                large: true
            }
            Label {
                objectName: "jobError"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: root.job !== null && root.job.state === "failed"
                text: (root.installed ? qsTr("Couldn't update. %1") : qsTr("Couldn't install. %1")).arg(root.store.jobError(root.job))
                color: Theme.errorColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            // Flathub flags apps whose metadata promises a phone layout.
            Item {
                objectName: "desktopWarning"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Math.max(warnIcon.height, warnText.height)
                visible: root.fullApp !== null && root.fullApp.isMobileFriendly === false

                Icon {
                    id: warnIcon
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-computer"
                    color: Theme.highlightColor
                }
                Label {
                    id: warnText
                    anchors.left: warnIcon.right
                    anchors.leftMargin: Theme.paddingMedium
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Designed for desktop. It may not fit a phone screen or work well by touch.")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }
            }

            BusyIndicator {
                objectName: "detailsBusy"
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Medium
                running: root.detailsLoading && root.fullApp === null
                visible: running
            }
            Column {
                objectName: "detailsFailed"
                width: parent.width
                visible: root.detailsFailed && !root.detailsLoading

                InfoLabel {
                    text: qsTr("Couldn't load details")
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Check your connection, then pull down to try again")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }
            }

            // ── Key facts ─────────────────────────────────
            Row {
                id: facts

                readonly property var cells: [
                    {
                        "top": root.rating ? root.rating.average.toFixed(1) : "–",
                        "bottom": root.rating ? qsTr("%1 ratings").arg(root.store.formatCount(root.rating.total)) : qsTr("No ratings")
                    },
                    {
                        "top": root.summary ? root.store.formatSize(root.summary.download_size) : "–",
                        "bottom": qsTr("Download")
                    },
                    {
                        "top": root.store.formatCount(root.store.installsFor(root.app)),
                        "bottom": qsTr("Installs")
                    }
                ]

                objectName: "facts"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: root.rating !== null || root.summary !== null || root.store.installsFor(root.app) > 0

                Repeater {
                    model: facts.cells
                    delegate: Column {
                        id: cell

                        required property var modelData

                        width: facts.width / facts.cells.length
                        Accessible.role: Accessible.StaticText
                        Accessible.name: modelData.top + " " + modelData.bottom

                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.top
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                            truncationMode: TruncationMode.Fade
                        }
                        Label {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: cell.modelData.bottom
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                        }
                    }
                }
            }

            // ── Screenshots ───────────────────────────────
            SilicaListView {
                id: shots

                // Phone screenshots get a tall strip; desktop ones are
                // landscape, so the strip shrinks to their shape instead of
                // letterboxing them in a portrait frame.
                readonly property var first: root.screenshots.length > 0 ? root.store.pickScreenshot(root.screenshots[0], 400) : null
                readonly property real aspect: first ? first.width / first.height : 0.6

                objectName: "screenshotStrip"
                width: parent.width
                height: aspect > 1 ? Math.round(root.width * 0.86 / aspect) : Math.round(root.height * 0.45)
                visible: root.screenshots.length > 0
                orientation: ListView.Horizontal
                spacing: Theme.paddingMedium
                leftMargin: Theme.horizontalPageMargin
                rightMargin: Theme.horizontalPageMargin
                clip: true
                model: root.screenshots
                delegate: BackgroundItem {
                    id: shot

                    required property var modelData
                    required property int index
                    readonly property var pick: root.store.pickScreenshot(modelData, shots.height)

                    height: shots.height
                    width: pick ? Math.min(height * pick.width / pick.height, root.width * 0.86) : height * 0.6
                    Accessible.name: qsTr("Screenshot %1 of %2").arg(index + 1).arg(root.screenshots.length)
                    onClicked: root.store.openScreenshots(root.screenshots, index)

                    Image {
                        anchors.fill: parent
                        source: shot.pick ? root.store.safeImageUrl(shot.pick.src) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }
                }

                HorizontalScrollDecorator {}
            }

            // ── What's new ────────────────────────────────
            Column {
                width: parent.width
                visible: root.latestRelease !== null

                SectionHeader {
                    text: qsTr("What's new")
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: root.latestRelease ? root.store.releaseLine(root.latestRelease) : ""
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: root.latestRelease && root.latestRelease.description ? root.store.cleanMarkup(root.latestRelease.description) : qsTr("No release notes for this version.")
                    textFormat: Text.StyledText
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                }
            }

            // ── About ─────────────────────────────────────
            Column {
                objectName: "aboutSection"
                width: parent.width
                visible: !!root.app.summary || !!root.app.description

                SectionHeader {
                    text: qsTr("About")
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: root.app.summary || ""
                    color: Theme.highlightColor
                    wrapMode: Text.Wrap
                }
                Label {
                    id: description
                    objectName: "description"
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    topPadding: Theme.paddingSmall
                    text: root.app.description ? root.store.cleanMarkup(root.app.description) : ""
                    textFormat: Text.StyledText
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                    maximumLineCount: root.descriptionExpanded ? 1000 : 6
                    elide: Text.ElideRight
                }
                BackgroundItem {
                    objectName: "moreItem"
                    width: parent.width
                    height: Theme.itemSizeSmall
                    visible: description.truncated || root.descriptionExpanded
                    Accessible.name: moreLabel.text
                    onClicked: root.descriptionExpanded = !root.descriptionExpanded

                    Label {
                        id: moreLabel
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.descriptionExpanded ? qsTr("Show less") : qsTr("Show more")
                        color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }

            // ── Ratings & reviews ─────────────────────────
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: root.rating !== null

                SectionHeader {
                    text: qsTr("Ratings & reviews")
                }

                Item {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: Math.max(score.height, histogram.height)

                    Column {
                        id: score
                        width: Theme.itemSizeHuge
                        Accessible.role: Accessible.StaticText
                        Accessible.name: root.rating ? qsTr("%1 out of 5, %2 ratings").arg(root.rating.average.toFixed(1)).arg(root.rating.total) : ""

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.rating ? root.rating.average.toFixed(1) : ""
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeHuge
                        }
                        StarRating {
                            anchors.horizontalCenter: parent.horizontalCenter
                            value: root.rating ? root.rating.average : 0
                            color: Theme.highlightColor
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: Theme.paddingSmall
                            text: root.rating ? qsTr("%1 ratings").arg(root.store.formatCount(root.rating.total)) : ""
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                        }
                    }

                    Column {
                        id: histogram
                        anchors.left: score.right
                        anchors.leftMargin: Theme.paddingLarge
                        anchors.right: parent.right
                        anchors.verticalCenter: score.verticalCenter
                        spacing: Theme.paddingSmall

                        Repeater {
                            model: [5, 4, 3, 2, 1]
                            delegate: Item {
                                id: histRow

                                required property int modelData

                                width: histogram.width
                                height: starCount.height

                                Label {
                                    id: starCount
                                    width: Theme.paddingLarge
                                    text: histRow.modelData
                                    color: Theme.secondaryHighlightColor
                                    font.pixelSize: Theme.fontSizeTiny
                                }
                                Rectangle {
                                    anchors.left: starCount.right
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: Theme.paddingSmall
                                    radius: height / 2
                                    color: Theme.rgba(Theme.highlightColor, Theme.opacityFaint)

                                    Rectangle {
                                        width: root.rating && root.rating.total > 0 ? parent.width * root.rating.counts[histRow.modelData] / root.rating.total : 0
                                        height: parent.height
                                        radius: parent.radius
                                        color: Theme.highlightColor
                                    }
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: root.reviews
                    delegate: Column {
                        id: review

                        required property var modelData

                        x: Theme.horizontalPageMargin
                        width: root.width - 2 * Theme.horizontalPageMargin
                        bottomPadding: Theme.paddingMedium

                        Label {
                            width: parent.width
                            text: review.modelData.summary || ""
                            color: Theme.highlightColor
                            truncationMode: TruncationMode.Fade
                        }
                        Row {
                            spacing: Theme.paddingSmall

                            StarRating {
                                anchors.verticalCenter: parent.verticalCenter
                                value: (review.modelData.rating || 0) / 20
                                color: Theme.highlightColor
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.store.reviewByline(review.modelData)
                                color: Theme.secondaryHighlightColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                            }
                        }
                        Label {
                            width: parent.width
                            topPadding: Theme.paddingSmall
                            text: review.modelData.description || ""
                            color: Theme.secondaryHighlightColor
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                            maximumLineCount: 5
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ── Permissions ───────────────────────────────
            // Flatpak sandbox holes, in plain words: the closest thing
            // Flathub has to a privacy label.
            Column {
                objectName: "sensitiveSection"
                width: parent.width
                spacing: Theme.paddingMedium
                visible: root.sensitivePermissions.length > 0

                SectionHeader {
                    text: qsTr("Sensitive access")
                }
                Repeater {
                    objectName: "sensitiveRows"
                    model: root.sensitivePermissions
                    delegate: permissionRow
                }
            }
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: root.summary !== null && (root.otherPermissions.length > 0 || root.sensitivePermissions.length === 0)

                SectionHeader {
                    text: root.sensitivePermissions.length > 0 ? qsTr("Other access") : qsTr("Permissions")
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: root.permissions.length === 0 ? qsTr("No special access: runs fully sandboxed") : qsTr("What this app can reach outside its sandbox")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.Wrap
                }
                Repeater {
                    objectName: "permissionRows"
                    model: root.otherPermissions
                    delegate: permissionRow
                }
            }

            // ── Information ───────────────────────────────
            Column {
                width: parent.width
                visible: infoRows.count > 0

                SectionHeader {
                    text: qsTr("Information")
                }
                Repeater {
                    id: infoRows
                    model: root.store.infoRows(root.app, root.summary)
                    delegate: DetailItem {
                        required property var modelData
                        label: modelData.label
                        value: modelData.value
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
