pragma ComponentBehavior: Bound

import MarathonApp.Store
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Theme
import QtQuick

// Editors' pick → Trending → Updates → Made for phones → New on Flathub.
Flickable {
    id: page

    required property var store

    contentWidth: width
    contentHeight: column.height + MSpacing.xl
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
        id: column
        width: page.width
        topPadding: page.store.dp(14)
        spacing: MSpacing.xl

        // ── Editors' pick ─────────────────────────────────
        // Per screens-apps-1.jsx:StoreDiscover: 135° teal-to-black card with
        // a radial glow from the top-right, text-only foreground. Height
        // follows the text, so a two-line name never clips the buttons.
        Item {
            id: hero
            x: MSpacing.md
            width: parent.width - MSpacing.md * 2
            height: heroText.implicitHeight + page.store.dp(18) * 2
            visible: page.store.heroApp !== null

            readonly property var app: page.store.heroApp

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    HapticService.light();
                    page.store.openDetail(hero.app);
                }
            }

            // Both layers are painted in one Canvas clipped to the card's
            // rounded rect: a Rectangle gradient can only run along an axis,
            // and the glow would otherwise spill past the corner it sits on.
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    const r = MRadius.lg;
                    ctx.clearRect(0, 0, width, height);
                    ctx.save();
                    ctx.beginPath();
                    ctx.roundedRect(0, 0, width, height, r, r);
                    ctx.clip();
                    const span = Math.max(width, height);
                    const bg = ctx.createLinearGradient(0, 0, span, span);
                    bg.addColorStop(0.0, "#1a4a3e");
                    bg.addColorStop(0.7, "#040404");
                    ctx.fillStyle = bg;
                    ctx.fillRect(0, 0, width, height);
                    // The spec's 200 px box sits 40 px off the right and 30 px
                    // off the top; CSS sizes a circle gradient to the box's
                    // farthest corner.
                    const gx = width - page.store.dp(60);
                    const gy = page.store.dp(70);
                    const glow = ctx.createRadialGradient(gx, gy, 0, gx, gy, page.store.dp(141));
                    glow.addColorStop(0.0, "rgba(0, 191, 165, 0.35)");
                    glow.addColorStop(0.6, "rgba(0, 191, 165, 0.0)");
                    ctx.fillStyle = glow;
                    ctx.fillRect(0, 0, width, height);
                    ctx.restore();
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
            Rectangle {
                anchors.fill: parent
                radius: MRadius.lg
                color: "transparent"
                border.width: 1
                border.color: MColors.tealBorder
            }

            Column {
                id: heroText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: page.store.dp(18)

                Rectangle {
                    width: pickText.implicitWidth + MSpacing.md
                    height: page.store.dp(22)
                    radius: MRadius.sm
                    color: MColors.marathonTealBright
                    Text {
                        id: pickText
                        anchors.centerIn: parent
                        text: "EDITORS' PICK"
                        color: "#000000"
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: Font.Bold
                        font.letterSpacing: MTypography.trackingEyebrow
                    }
                }

                Row {
                    topPadding: page.store.dp(14)
                    width: parent.width
                    spacing: page.store.dp(14)

                    AppIcon {
                        id: heroIcon
                        width: page.store.dp(64)
                        height: width
                        source: hero.app ? page.store.safeImageUrl(hero.app.icon || "") : ""
                    }
                    Column {
                        anchors.verticalCenter: heroIcon.verticalCenter
                        width: parent.width - heroIcon.width - parent.spacing
                        Text {
                            width: parent.width
                            text: hero.app ? (hero.app.name || hero.app.app_id || "") : ""
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeTitle3
                            font.weight: Font.Medium
                            font.letterSpacing: MTypography.trackingTitle3
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: hero.app ? (hero.app.developer_name || "") : ""
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    width: parent.width
                    topPadding: page.store.dp(12)
                    text: hero.app ? (hero.app.summary || "") : ""
                    color: MColors.textPrimary
                    opacity: 0.85
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Item {
                    width: parent.width
                    height: page.store.dp(14)
                }

                GetButton {
                    store: page.store
                    appId: hero.app ? (hero.app.app_id || hero.app.id || "") : ""
                    prominent: true
                }
            }
        }

        // ── Trending ──────────────────────────────────────
        Column {
            width: parent.width
            spacing: page.store.dp(10)
            visible: page.store.trendingApps.length > 0

            SectionHeader {
                width: parent.width
                title: "Trending now"
                subtitle: "Most installed in the last two weeks"
            }

            Row {
                id: trendRow
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                spacing: MSpacing.sm

                Repeater {
                    model: page.store.trendingApps
                    delegate: Column {
                        id: tile
                        required property var modelData
                        readonly property string appId: tile.modelData.app_id || tile.modelData.id || ""
                        readonly property var rating: page.store.ratingFor(tile.appId)

                        width: (trendRow.width - trendRow.spacing * 2) / 3
                        Component.onCompleted: {
                            page.store.ensureCategory(tile.modelData);
                            page.store.ensureRating(tile.appId);
                        }

                        AppIcon {
                            width: parent.width
                            height: width
                            source: page.store.safeImageUrl(tile.modelData.icon || "")
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    page.store.openDetail(tile.modelData);
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            topPadding: page.store.dp(8)
                            text: tile.modelData.name || tile.appId
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: page.store.categoryLabel(tile.modelData)
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeCaption
                            elide: Text.ElideRight
                        }
                        Row {
                            topPadding: page.store.dp(3)
                            spacing: page.store.dp(4)
                            visible: tile.rating !== null
                            StarRating {
                                anchors.verticalCenter: parent.verticalCenter
                                value: tile.rating ? tile.rating.average : 0
                                starSize: page.store.dp(9)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tile.rating ? tile.rating.average.toFixed(1) : ""
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeCaption
                            }
                        }
                    }
                }
            }
        }

        // ── Updates ───────────────────────────────────────
        Column {
            width: parent.width
            spacing: page.store.dp(10)
            visible: page.store.updateApps.length > 0

            SectionHeader {
                width: parent.width
                title: "Updates available"
                subtitle: page.store.updateApps.length === 1 ? "1 app" : page.store.updateApps.length + " apps"
                actionText: "Update all"
                onActionClicked: page.store.updateAll()
            }
            AppListCard {
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                store: page.store
                model: page.store.updateApps
            }
        }

        // ── Made for phones ───────────────────────────────
        // Flathub's mobile collection: apps that declare a phone form factor.
        Column {
            width: parent.width
            spacing: page.store.dp(10)
            visible: page.store.mobileApps.length > 0

            SectionHeader {
                width: parent.width
                title: "Made for phones"
                subtitle: "Apps that fit a small touch screen"
                actionText: "See all"
                onActionClicked: page.store.openCollection("mobile", "Made for phones")
            }
            AppListCard {
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                store: page.store
                model: page.store.mobileApps
            }
        }

        // ── New on Flathub ────────────────────────────────
        Column {
            width: parent.width
            spacing: page.store.dp(10)
            visible: page.store.newApps.length > 0

            SectionHeader {
                width: parent.width
                title: "New on Flathub"
                actionText: "See all"
                onActionClicked: page.store.openCollection("recently-added", "New on Flathub")
            }
            AppListCard {
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                store: page.store
                model: page.store.newApps
            }
        }

        MActivityIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.store.catalogLoading && page.store.catalogAppCount === 0
        }

        // Column rejects vertical anchors; MEmptyState sizes itself and is
        // centred horizontally like every other child here.
        MEmptyState {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - MSpacing.lg * 2
            visible: !page.store.catalogLoading && page.store.catalogAppCount === 0
            iconName: "wifi-slash"
            iconSize: page.store.dp(64)
            title: "Can't reach Flathub"
            message: page.store.lastError !== "" ? "Check your connection and try again.\n(" + page.store.lastError + ")" : "Check your connection and try again."
        }

        MButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !page.store.catalogLoading && page.store.catalogAppCount === 0
            text: "Try again"
            variant: "secondary"
            onClicked: page.store.loadCatalog()
        }
    }
}
