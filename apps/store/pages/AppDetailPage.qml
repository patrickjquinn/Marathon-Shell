pragma ComponentBehavior: Bound

import MarathonApp.Store
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

// One app: header, key facts, screenshots, what's new, description,
// ratings and reviews, permissions, information.
Rectangle {
    id: page

    required property var store
    required property string appId
    // The list entry the user tapped, shown until the full record lands.
    property var summaryApp: null
    property var fullApp: null
    property var summary: null
    property var reviews: []
    property bool descriptionExpanded: false

    readonly property var app: fullApp || summaryApp || ({})
    readonly property var rating: store.ratingFor(appId)
    readonly property var screenshots: app.screenshots || []
    readonly property var latestRelease: (app.releases && app.releases.length > 0) ? app.releases[0] : null
    readonly property var permissions: summary && summary.metadata ? store.describePermissions(summary.metadata.permissions) : []
    readonly property bool installed: store.isInstalled(appId)

    color: MColors.background
    Component.onCompleted: {
        store.ensureRating(appId);
        store.loadAppstream(appId, function (full) {
            page.fullApp = full;
        });
        store.loadSummary(appId, function (s) {
            page.summary = s;
        });
        store.loadReviews(appId, function (list) {
            page.reviews = list;
        });
    }

    MTopBar {
        id: bar
        width: parent.width
        minimized: true
        showBack: true
        // The name moves into the bar once the header has scrolled away.
        title: flick.contentY > header.height ? (page.app.name || "") : ""
        onBackClicked: page.store.goBack()
        z: 2
    }

    Flickable {
        id: flick
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        contentHeight: body.height + MSpacing.xxl
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: flick.width
            spacing: MSpacing.lg

            // ── Header ────────────────────────────────────
            Item {
                id: header
                width: parent.width
                height: headerRow.height + MSpacing.lg

                Row {
                    id: headerRow
                    x: MSpacing.md
                    y: MSpacing.md
                    width: parent.width - MSpacing.md * 2
                    spacing: page.store.dp(16)

                    AppIcon {
                        id: bigIcon
                        width: page.store.dp(96)
                        height: width
                        source: page.store.iconFor(page.app)
                    }

                    Column {
                        width: parent.width - bigIcon.width - parent.spacing
                        spacing: page.store.dp(3)

                        Text {
                            width: parent.width
                            text: page.app.name || page.appId
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeTitle2
                            font.weight: Font.Medium
                            font.letterSpacing: MTypography.trackingTitle2
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Row {
                            spacing: page.store.dp(4)
                            width: parent.width
                            Text {
                                id: developer
                                width: Math.min(implicitWidth, parent.width - (verified.visible ? verified.width + parent.spacing : 0))
                                text: page.app.developer_name || ""
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                elide: Text.ElideRight
                            }
                            Icon {
                                id: verified
                                anchors.verticalCenter: developer.verticalCenter
                                visible: page.store.isVerified(page.app)
                                name: "seal-check"
                                size: page.store.dp(15)
                                color: MColors.marathonTealBright
                            }
                        }
                        Item {
                            width: 1
                            height: page.store.dp(8)
                        }
                        GetButton {
                            store: page.store
                            appId: page.appId
                            large: true
                        }
                        Text {
                            readonly property var job: page.store.jobFor(page.appId)
                            width: parent.width
                            topPadding: page.store.dp(6)
                            visible: job !== null && job.state === "failed"
                            text: "Couldn't " + (job && job.state === "failed" && page.installed ? "update" : "install") + ". " + page.store.jobError(job)
                            color: MColors.error
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // Flathub flags apps whose metadata promises a phone layout.
            Rectangle {
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                height: warnText.implicitHeight + page.store.dp(20)
                radius: MRadius.lg
                visible: page.fullApp !== null && page.fullApp.isMobileFriendly === false
                color: MColors.elev2
                border.width: 1
                border.color: Qt.rgba(MColors.warning.r, MColors.warning.g, MColors.warning.b, 0.35)

                Icon {
                    id: warnIcon
                    x: page.store.dp(12)
                    anchors.verticalCenter: parent.verticalCenter
                    name: "desktop"
                    size: page.store.dp(20)
                    color: MColors.warning
                }
                Text {
                    id: warnText
                    anchors.left: warnIcon.right
                    anchors.leftMargin: page.store.dp(10)
                    anchors.right: parent.right
                    anchors.rightMargin: page.store.dp(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Designed for desktop. It may not fit a phone screen or work well by touch."
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    wrapMode: Text.WordWrap
                }
            }

            // ── Key facts ─────────────────────────────────
            Row {
                id: facts
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                height: page.store.dp(64)

                readonly property var cells: [
                    {
                        "top": page.rating ? page.rating.average.toFixed(1) : "–",
                        "bottom": page.rating ? page.store.formatCount(page.rating.total) + " ratings" : "No ratings",
                        "stars": page.rating !== null
                    },
                    {
                        "top": page.summary ? page.store.formatSize(page.summary.download_size) : "–",
                        "bottom": "Download"
                    },
                    {
                        "top": page.store.categoryLabel(page.app),
                        "bottom": "Category"
                    },
                    {
                        "top": page.store.formatCount(page.store.installsFor(page.app)),
                        "bottom": "Installs"
                    }
                ]

                Repeater {
                    model: facts.cells
                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: facts.width / 4
                        height: facts.height

                        Rectangle {
                            visible: cell.index > 0
                            width: 1
                            height: parent.height * 0.6
                            anchors.verticalCenter: parent.verticalCenter
                            color: MColors.whiteOverlay08
                        }
                        Column {
                            anchors.centerIn: parent
                            width: parent.width - page.store.dp(8)
                            spacing: page.store.dp(3)
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData.top
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeHeadline
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StarRating {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: cell.modelData.stars === true
                                value: page.rating ? page.rating.average : 0
                                starSize: page.store.dp(9)
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.modelData.bottom
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeCaption
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // ── Screenshots ───────────────────────────────
            ListView {
                id: shots
                // Phone screenshots get a tall strip; desktop ones are
                // landscape, so the strip shrinks to their shape instead of
                // letterboxing them in a portrait frame.
                readonly property var first: page.screenshots.length > 0 ? page.store.pickScreenshot(page.screenshots[0], 400) : null
                readonly property real aspect: first ? first.width / first.height : 0.6
                width: parent.width
                height: aspect > 1 ? Math.round(page.width * 0.86 / aspect) : page.store.dp(380)
                visible: page.screenshots.length > 0
                orientation: ListView.Horizontal
                spacing: MSpacing.sm
                leftMargin: MSpacing.md
                rightMargin: MSpacing.md
                clip: true
                model: page.screenshots
                delegate: Rectangle {
                    id: shot
                    required property var modelData
                    required property int index
                    readonly property var pick: page.store.pickScreenshot(modelData, shots.height)

                    height: shots.height
                    width: pick ? Math.min(height * pick.width / pick.height, page.width * 0.86) : height * 0.6
                    radius: MRadius.lg
                    color: MColors.elev2
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: shot.pick ? page.store.safeImageUrl(shot.pick.src) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        mipmap: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.width: 1
                        border.color: MColors.whiteOverlay08
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: page.store.openScreenshots(page.screenshots, shot.index)
                    }
                }
            }

            // ── What's new ────────────────────────────────
            Column {
                width: parent.width
                spacing: page.store.dp(6)
                visible: page.latestRelease !== null

                SectionHeader {
                    width: parent.width
                    title: "What's new"
                    subtitle: page.latestRelease ? page.store.releaseLine(page.latestRelease) : ""
                }
                Text {
                    x: MSpacing.md
                    width: parent.width - MSpacing.md * 2
                    text: page.latestRelease && page.latestRelease.description ? page.store.cleanMarkup(page.latestRelease.description) : "No release notes for this version."
                    textFormat: Text.StyledText
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    lineHeight: 1.3
                    wrapMode: Text.WordWrap
                    maximumLineCount: 6
                    elide: Text.ElideRight
                }
            }

            // ── About ─────────────────────────────────────
            Column {
                width: parent.width
                spacing: page.store.dp(6)

                SectionHeader {
                    width: parent.width
                    title: "About"
                }
                Text {
                    x: MSpacing.md
                    width: parent.width - MSpacing.md * 2
                    text: page.app.summary || ""
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeHeadline
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                }
                Text {
                    id: description
                    x: MSpacing.md
                    width: parent.width - MSpacing.md * 2
                    text: page.app.description ? page.store.cleanMarkup(page.app.description) : ""
                    textFormat: Text.StyledText
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    lineHeight: 1.3
                    wrapMode: Text.WordWrap
                    maximumLineCount: page.descriptionExpanded ? 1000 : 6
                    elide: Text.ElideRight
                }
                Text {
                    x: MSpacing.md
                    visible: description.truncated || page.descriptionExpanded
                    text: page.descriptionExpanded ? "Less" : "More"
                    color: MColors.marathonTealBright
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    font.weight: Font.Medium
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -MSpacing.sm
                        onClicked: page.descriptionExpanded = !page.descriptionExpanded
                    }
                }
            }

            // ── Ratings & reviews ─────────────────────────
            Column {
                width: parent.width
                spacing: page.store.dp(12)
                visible: page.rating !== null

                SectionHeader {
                    width: parent.width
                    title: "Ratings & reviews"
                }

                Row {
                    x: MSpacing.md
                    width: parent.width - MSpacing.md * 2
                    spacing: MSpacing.lg

                    Column {
                        id: scoreColumn
                        width: page.store.dp(96)
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: page.rating ? page.rating.average.toFixed(1) : ""
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeTitleL
                            font.weight: Font.Light
                        }
                        StarRating {
                            anchors.horizontalCenter: parent.horizontalCenter
                            value: page.rating ? page.rating.average : 0
                            starSize: page.store.dp(12)
                            color: MColors.textPrimary
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            topPadding: page.store.dp(4)
                            text: page.rating ? page.store.formatCount(page.rating.total) + " ratings" : ""
                            color: MColors.textTertiary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeCaption
                        }
                    }

                    Column {
                        anchors.verticalCenter: scoreColumn.verticalCenter
                        width: parent.width - scoreColumn.width - parent.spacing
                        spacing: page.store.dp(4)
                        Repeater {
                            model: [5, 4, 3, 2, 1]
                            delegate: Row {
                                id: histRow
                                required property int modelData
                                width: parent.width
                                spacing: page.store.dp(8)
                                Text {
                                    width: page.store.dp(10)
                                    text: histRow.modelData
                                    color: MColors.textTertiary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeCaption
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - page.store.dp(18)
                                    height: page.store.dp(5)
                                    radius: height / 2
                                    color: MColors.whiteOverlay08
                                    Rectangle {
                                        width: page.rating && page.rating.total > 0 ? parent.width * page.rating.counts[histRow.modelData] / page.rating.total : 0
                                        height: parent.height
                                        radius: parent.radius
                                        color: MColors.textSecondary
                                    }
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: page.reviews
                    delegate: Rectangle {
                        id: card
                        required property var modelData
                        x: MSpacing.md
                        width: page.width - MSpacing.md * 2
                        height: reviewBody.height + page.store.dp(28)
                        radius: MRadius.lg
                        color: MColors.elev2
                        border.width: 1
                        border.color: MColors.whiteOverlay06

                        Column {
                            id: reviewBody
                            x: page.store.dp(14)
                            y: page.store.dp(14)
                            width: parent.width - page.store.dp(28)
                            spacing: page.store.dp(4)
                            Text {
                                width: parent.width
                                text: card.modelData.summary || ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Row {
                                spacing: page.store.dp(8)
                                StarRating {
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: (card.modelData.rating || 0) / 20
                                    starSize: page.store.dp(10)
                                    color: MColors.textPrimary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.store.reviewByline(card.modelData)
                                    color: MColors.textTertiary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeCaption
                                }
                            }
                            Text {
                                width: parent.width
                                topPadding: page.store.dp(4)
                                text: card.modelData.description || ""
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                lineHeight: 1.25
                                wrapMode: Text.WordWrap
                                maximumLineCount: 5
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // ── Permissions ───────────────────────────────
            // Flatpak sandbox holes, in plain words: the closest thing
            // Flathub has to a privacy label.
            Column {
                width: parent.width
                spacing: page.store.dp(8)
                visible: page.summary !== null

                SectionHeader {
                    width: parent.width
                    title: "Permissions"
                    subtitle: page.permissions.length === 0 ? "No special access: runs fully sandboxed" : "What this app can reach outside its sandbox"
                }
                Repeater {
                    model: page.permissions
                    delegate: Row {
                        id: perm
                        required property var modelData
                        x: MSpacing.md
                        width: page.width - MSpacing.md * 2
                        spacing: page.store.dp(12)
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: perm.modelData.icon
                            size: page.store.dp(20)
                            color: perm.modelData.risky ? MColors.warning : MColors.textSecondary
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - page.store.dp(32)
                            Text {
                                width: parent.width
                                text: perm.modelData.label
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                            }
                            Text {
                                width: parent.width
                                text: perm.modelData.detail
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeCaption
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            // ── Information ───────────────────────────────
            Column {
                width: parent.width
                spacing: page.store.dp(2)

                SectionHeader {
                    width: parent.width
                    title: "Information"
                }
                Repeater {
                    model: page.store.infoRows(page.app, page.summary)
                    delegate: Item {
                        id: info
                        required property var modelData
                        x: MSpacing.md
                        width: page.width - MSpacing.md * 2
                        height: page.store.dp(44)
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: info.modelData.label
                            color: MColors.textTertiary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeSubhead
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * 0.6
                            horizontalAlignment: Text.AlignRight
                            text: info.modelData.value
                            color: info.modelData.url ? MColors.marathonTealBright : MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeSubhead
                            elide: Text.ElideMiddle
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: MColors.whiteOverlay04
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: info.modelData.url !== undefined
                            onClicked: Qt.openUrlExternally(info.modelData.url)
                        }
                    }
                }
            }

            MButton {
                x: MSpacing.md
                visible: page.installed
                text: "Uninstall"
                variant: "secondary"
                textColor: MColors.error
                onClicked: confirm.show()
            }
        }
    }

    MConfirmDialog {
        id: confirm
        title: "Uninstall " + (page.app.name || page.appId) + "?"
        message: "The app and its data in the sandbox will be removed."
        confirmText: "Uninstall"
        onConfirmed: page.store.uninstallApp(page.appId)
    }
}
