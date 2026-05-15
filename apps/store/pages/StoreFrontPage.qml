import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Marathon DS · Store · Discover (screens-apps-2.jsx:StoreDiscover).
//
// MTopBar "Store" + 32 px avatar. Hero card with EDITORS' PICK chip,
// featured title + author + Get + Preview. "Trending now" 3-up tile
// row (icon + name + rating). "Updates available · N" rows with
// Update buttons. Bottom tabs handled by parent (Discover / Apps /
// Installed / Account).
//
// All content is sourced from AppStoreService over DBus
// (MarathonAppStoreService in the shell). The previous version of
// this file shipped hard-coded JSON for the featured / trending /
// updates lists; that masked the fact that there was a real catalog
// backend behind the IPC boundary the whole time. Empty states cover
// "no catalog yet" so the layout doesn't collapse on a cold device.
Rectangle {
    id: page

    anchors.fill: parent
    color: MColors.background

    // Reactive arrays — bound to the AppStoreService catalog state via
    // a `_tick` property that flips on catalogRefreshed signals. Every
    // *Apps property re-evaluates when _tick advances, pulling the
    // latest data out of the live service. Using a tick (rather than
    // function calls in bindings) is the same pattern Notes uses for
    // its folders/tasks derivations — QML can't track function-call
    // dependencies otherwise.
    property int _tick: 0

    readonly property bool serviceAvailable: typeof AppStoreService !== "undefined" && AppStoreService !== null
    readonly property bool catalogReady: serviceAvailable && AppStoreService.catalogLoaded
    readonly property bool catalogLoading: serviceAvailable && AppStoreService.loading

    readonly property var featuredApps: {
        const _ = page._tick;
        if (!serviceAvailable)
            return [];
        return AppStoreService.getFeaturedApps() || [];
    }
    readonly property var availableUpdates: {
        const _ = page._tick;
        if (!serviceAvailable)
            return [];
        return AppStoreService.getAvailableUpdates() || [];
    }
    // Trending = first 3 catalog entries that aren't featured. Avoids
    // duplicating the hero card in the trending row.
    readonly property var trendingApps: {
        const _ = page._tick;
        if (!serviceAvailable)
            return [];
        const all = AppStoreService.searchApps("") || [];
        const featured = page.featuredApps;
        const featuredIds = {};
        for (let i = 0; i < featured.length; i++)
            featuredIds[featured[i].id] = true;
        const out = [];
        for (let i = 0; i < all.length && out.length < 3; i++) {
            if (!featuredIds[all[i].id])
                out.push(all[i]);
        }
        return out;
    }
    readonly property var heroApp: featuredApps.length > 0 ? featuredApps[0] : null
    readonly property bool showEmptyState: featuredApps.length === 0 && trendingApps.length === 0 && availableUpdates.length === 0

    Component.onCompleted: {
        if (serviceAvailable && !AppStoreService.catalogLoaded)
            AppStoreService.refreshCatalog();
    }

    Connections {
        function onCatalogRefreshed() {
            page._tick = page._tick + 1;
        }
        function onStateChanged() {
            page._tick = page._tick + 1;
        }
        target: page.serviceAvailable ? AppStoreService : null
    }

    // Empty-state overlay sits on top of the page Rectangle so its
    // anchors resolve against the full page area rather than the
    // Flickable contentItem. Visible only while there's nothing in
    // the catalog to show.
    MEmptyState {
        anchors.fill: parent
        anchors.topMargin: 96
        anchors.bottomMargin: 16
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        visible: page.showEmptyState
        iconName: page.catalogLoading ? "refresh-cw" : "download-cloud"
        iconSize: 64
        title: page.catalogLoading ? "Loading catalog…" : "No Apps Available"
        message: page.catalogLoading ? "Talking to " + (page.serviceAvailable ? AppStoreService.repositoryUrl : "the Marathon catalog") : "The Marathon catalog couldn't be reached. Try again once you're online."
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header ─────────────────────────────────────────
        MTopBar {
            id: topBar
            width: parent.width
            title: "Store"
            actions: [
                Rectangle {
                    width: 32
                    height: 32
                    radius: width / 2
                    color: MColors.elev3
                    border.width: 1
                    border.color: MColors.whiteOverlay08
                    Icon {
                        anchors.centerIn: parent
                        name: "user"
                        size: 16
                        color: MColors.textSecondary
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: HapticService.light()
                    }
                }
            ]
        }

        Flickable {
            id: scrollArea
            width: parent.width
            height: parent.height - topBar.height
            clip: true
            visible: !page.showEmptyState
            contentHeight: contentCol.height
            contentWidth: width

            Column {
                id: contentCol
                width: parent.width
                spacing: 18
                topPadding: 16
                bottomPadding: 20
                visible: page.featuredApps.length > 0 || page.trendingApps.length > 0 || page.availableUpdates.length > 0

                // ── Editors' Pick hero ──
                // JSX ref: linear-gradient(135deg, #1a4a3e 0%, #040404 70%)
                // dark teal → black diagonal, with a top-right radial
                // glow at ~35% teal-bright fading to transparent. The
                // gradient gives the hero card weight; without it the
                // pick read as just another secondary card.
                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    visible: page.heroApp !== null
                    height: 200
                    clip: true
                    // Underlying gradient surface.
                    Rectangle {
                        anchors.fill: parent
                        radius: MRadius.md
                        border.width: 1
                        border.color: MColors.tealBorder
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop {
                                position: 0
                                color: "#1a4a3e"
                            }
                            GradientStop {
                                position: 0.7
                                color: "#040404"
                            }
                        }
                    }
                    // Top-right radial glow — generously sized so the
                    // teal bleeds into the upper third of the card per
                    // the JSX spec rather than sitting in just a corner.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -60
                        anchors.rightMargin: -60
                        width: 220
                        height: 220
                        radius: width / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0
                                color: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
                            }
                            GradientStop {
                                position: 1
                                color: Qt.rgba(0, 191 / 255, 165 / 255, 0.0)
                            }
                        }
                    }
                    // Top-edge inset highlight per DS "lit from above"
                    // treatment — matches buttons + cards.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 1
                        anchors.rightMargin: 1
                        anchors.topMargin: 1
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.10)
                    }

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        anchors.topMargin: 16
                        anchors.bottomMargin: 16
                        spacing: 8

                        Rectangle {
                            width: pickText.implicitWidth + 16
                            height: 22
                            radius: 2
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

                        Text {
                            text: page.heroApp ? (page.heroApp.name || page.heroApp.id || "") : ""
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: 22
                            font.weight: Font.Medium
                            font.letterSpacing: -0.3
                            lineHeight: 1.15
                            wrapMode: Text.WordWrap
                            width: parent.width
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        // Author · pricing line. `pricing` is the
                        // human-friendly string ("Free with in-app pro
                        // tier"); we fall back to "Free" when the field
                        // is missing.
                        Text {
                            text: {
                                if (!page.heroApp)
                                    return "";
                                const author = page.heroApp.author || "Unknown";
                                const pricing = page.heroApp.pricing ? page.heroApp.pricing : (page.heroApp.price && page.heroApp.price !== 0 ? page.heroApp.price : "Free");
                                return author + " · " + pricing;
                            }
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        Item {
                            width: parent.width
                            height: 6
                        }

                        Row {
                            spacing: 8
                            MButton {
                                text: "Get"
                                variant: "primary"
                                size: "compact"
                                onClicked: {
                                    if (page.heroApp && page.serviceAvailable)
                                        AppStoreService.downloadApp(page.heroApp.id);
                                }
                            }
                            MButton {
                                text: "Preview"
                                variant: "ghost"
                                size: "compact"
                            }
                        }
                    }
                }

                // ── Trending now ────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: page.trendingApps.length > 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Trending now"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        font.letterSpacing: -0.2
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Top picks from across the catalog"
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 8
                        spacing: 10

                        Repeater {
                            model: page.trendingApps
                            // Each tile is a stylized app-icon mockup:
                            // a coloured squircle with the app's Lucide
                            // glyph centered inside. Background +
                            // foreground colors come from the catalog
                            // entry (iconBackground / iconForeground)
                            // so tiles read as distinct apps rather
                            // than identical placeholders. Defaults
                            // are elev-3 + textPrimary for entries
                            // that didn't ship a tint.
                            delegate: Column {
                                width: (parent.width - parent.spacing * 2) / 3
                                spacing: 8

                                readonly property string tileBg: modelData.iconBackground || MColors.elev3
                                readonly property string tileFg: modelData.iconForeground || MColors.textPrimary

                                // Icon tile with the DS "lit from
                                // above" treatment: bottom shadow
                                // (1 px black at 60%) on the outer
                                // edge, 1 px white-15 inset highlight
                                // along the top — matches the JSX
                                // boxShadow: 0 0 0 1px rgba(0,0,0,0.6),
                                //   inset 0 1px 0 rgba(255,255,255,0.15)
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: width
                                    radius: 4
                                    color: tileBg
                                    border.width: 1
                                    border.color: Qt.rgba(0, 0, 0, 0.6)
                                    Icon {
                                        anchors.centerIn: parent
                                        name: modelData.iconName || modelData.icon || "package"
                                        size: 38
                                        color: tileFg
                                    }
                                    // Top-edge inset highlight only.
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.leftMargin: 1
                                        anchors.rightMargin: 1
                                        anchors.topMargin: 1
                                        height: 1
                                        color: Qt.rgba(1, 1, 1, 0.15)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: HapticService.light()
                                    }
                                }

                                Text {
                                    anchors.left: parent.left
                                    text: modelData.name || modelData.id || ""
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    anchors.left: parent.left
                                    // "Category · ★ rating" per JSX —
                                    // the star prefix on the rating
                                    // sells the subhead as a real app
                                    // store metric rather than just a
                                    // number trailing the category.
                                    text: {
                                        const cat = modelData.category || "App";
                                        const rating = modelData.rating;
                                        if (rating && rating > 0)
                                            return cat + " · ★ " + Number(rating).toFixed(1);
                                        return cat;
                                    }
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }
                    }
                }

                // ── Updates available ────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: page.availableUpdates.length > 0

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Updates available · " + page.availableUpdates.length
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        font.letterSpacing: -0.2
                    }

                    // Updates rows live inside an MCard so the
                    // group reads as a single surface, with row
                    // dividers between entries (matches the JSX
                    // Card-wrapping-m-row layout). Each row uses
                    // the catalog's iconBackground + iconForeground
                    // for the row-icon bay so the apps stay
                    // visually distinct.
                    MCard {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        elevation: 2
                        height: rowsCol.height + 4

                        Column {
                            id: rowsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: -10
                            anchors.rightMargin: -10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            Repeater {
                                model: page.availableUpdates
                                delegate: Item {
                                    width: parent.width
                                    height: 62

                                    readonly property string rowIconBg: modelData.iconBackground || MColors.elev3
                                    readonly property string rowIconFg: modelData.iconForeground || MColors.textSecondary

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 12

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 38
                                            height: 38
                                            radius: 4
                                            color: rowIconBg
                                            border.width: 1
                                            border.color: Qt.rgba(0, 0, 0, 0.6)
                                            Icon {
                                                anchors.centerIn: parent
                                                name: modelData.iconName || modelData.icon || "package"
                                                size: 18
                                                color: rowIconFg
                                            }
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.leftMargin: 1
                                                anchors.rightMargin: 1
                                                anchors.topMargin: 1
                                                height: 1
                                                color: Qt.rgba(1, 1, 1, 0.15)
                                            }
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 38 - 92 - parent.spacing * 2
                                            spacing: 2
                                            Text {
                                                text: modelData.name || modelData.id || ""
                                                color: MColors.textPrimary
                                                font.family: MTypography.fontFamily
                                                font.pixelSize: MTypography.sizeSubhead
                                                font.weight: Font.Medium
                                            }
                                            Text {
                                                width: parent.width
                                                // "Notes · 24.6 MB" — JSX spec
                                                // pairs the release notes with the
                                                // download size on a single line so
                                                // users see both at a glance.
                                                text: {
                                                    const notes = modelData.updateNotes || modelData.description || ("Version " + (modelData.latestVersion || modelData.version || ""));
                                                    const size = modelData.downloadSize || "";
                                                    return size ? (notes + " · " + size) : notes;
                                                }
                                                color: MColors.textSecondary
                                                font.family: MTypography.fontFamily
                                                font.pixelSize: MTypography.sizeFootnote
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MButton {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "Update"
                                            variant: "primary"
                                            size: "compact"
                                            onClicked: {
                                                if (page.serviceAvailable)
                                                    AppStoreService.downloadApp(modelData.id);
                                            }
                                        }
                                    }

                                    Rectangle {
                                        visible: index < page.availableUpdates.length - 1
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 14 + 38 + 12
                                        anchors.rightMargin: 14
                                        height: 1
                                        color: MColors.whiteOverlay04
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
