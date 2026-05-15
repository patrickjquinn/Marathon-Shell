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
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    visible: page.heroApp !== null
                    height: 160
                    radius: MRadius.md
                    color: MColors.elev2
                    border.width: 1
                    border.color: MColors.tealBorder

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -20
                        anchors.rightMargin: -20
                        width: 140
                        height: 140
                        radius: width / 2
                        color: MColors.marathonTealBright
                        opacity: 0.10
                    }

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 14
                        anchors.bottomMargin: 14
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
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            font.letterSpacing: -0.2
                            wrapMode: Text.WordWrap
                            width: parent.width
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            text: {
                                if (!page.heroApp)
                                    return "";
                                const author = page.heroApp.author || "Unknown";
                                const pricing = page.heroApp.price === 0 || page.heroApp.price === "0" || !page.heroApp.price ? "Free" : page.heroApp.price;
                                return author + " · " + pricing;
                            }
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            elide: Text.ElideRight
                            width: parent.width
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
                                variant: "secondary"
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
                            delegate: Column {
                                width: (parent.width - parent.spacing * 2) / 3
                                spacing: 6

                                readonly property bool highlightFirst: index === 0

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: width
                                    radius: MRadius.squircle
                                    color: highlightFirst ? MColors.marathonTealBright : MColors.elev3
                                    border.width: 1
                                    border.color: highlightFirst ? MColors.tealBorder : MColors.whiteOverlay08
                                    Icon {
                                        anchors.centerIn: parent
                                        name: modelData.iconName || modelData.icon || "package"
                                        size: 32
                                        color: highlightFirst ? "#000000" : MColors.textPrimary
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: HapticService.light()
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.name || modelData.id || ""
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: {
                                        const cat = modelData.category || "App";
                                        const rating = modelData.rating;
                                        if (rating && rating > 0)
                                            return cat + " · " + Number(rating).toFixed(1);
                                        return cat;
                                    }
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeEyebrow
                                    elide: Text.ElideRight
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
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

                    Repeater {
                        model: page.availableUpdates
                        delegate: Item {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            height: 60

                            Row {
                                anchors.fill: parent
                                spacing: 12

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 40
                                    height: 40
                                    radius: MRadius.squircle
                                    color: MColors.elev3
                                    border.width: 1
                                    border.color: MColors.whiteOverlay08
                                    Icon {
                                        anchors.centerIn: parent
                                        name: modelData.iconName || modelData.icon || "package"
                                        size: 18
                                        color: MColors.textSecondary
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 40 - 80 - parent.spacing * 2
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
                                        text: modelData.updateNotes || modelData.description || ("Version " + (modelData.latestVersion || modelData.version || ""))
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
                        }
                    }
                }
            }
        }
    }
}
