pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../core/LauncherGrid.js" as LauncherGrid

Item {
    id: appGrid

    property var appModel: null
    property int pageIndex: 0
    // The window's size, which is the screen's on a phone; LauncherGrid's
    // pager uses the same.
    property int columns: LauncherGrid.columns(Window.width > 0 ? Window.width : Constants.screenWidth, Silica.Theme.pixelRatio, SettingsManagerCpp.appGridColumns)
    property int rows: LauncherGrid.rows(Window.height > 0 ? Window.height : Constants.screenHeight, Silica.Theme.iconSizeLauncher)
    property int itemsPerPage: columns * rows
    property real searchPullProgress: 0
    property bool searchGestureActive: false
    // Icons wait hidden for playEntrance().
    property bool entranceHeld: false
    // App management: icons settle into tiles, removable ones carry an ✕, a
    // tap opens the app's info. The page view owns it, so it spans every page.
    property bool editing: false
    // Apps being uninstalled, by id; their icons stay hidden until they go.
    property var removing: ({})
    readonly property int startIndex: pageIndex * itemsPerPage
    readonly property int pageItemCount: {
        if (!appModel)
            return 0;

        var remaining = appModel.count - startIndex;
        return Math.max(0, Math.min(remaining, itemsPerPage));
    }
    // Unread counts for this page's apps, as {index, count}. Only badged
    // icons get an overlay.
    readonly property var badges: {
        const notifications = NotificationService.notifications;
        if (!appModel || !SettingsManagerCpp.showNotificationBadges || notifications.length === 0)
            return [];
        const out = [];
        for (let i = 0; i < pageItemCount; ++i) {
            const app = appModel.getAppAtIndex(startIndex + i);
            const count = app ? NotificationService.getNotificationCountForApp(app.id) : 0;
            if (count > 0)
                out.push({
                    "index": i,
                    "count": count
                });
        }
        return out;
    }

    signal appLaunched(var app)
    signal editRequested
    signal editDone
    signal uninstallConfirmed(var app)

    // The icons rise in one after another, as setup hands over.
    function playEntrance() {
        for (let i = 0; i < iconRepeater.count; ++i)
            (iconRepeater.itemAt(i) as IconCell).playEntrance();
    }

    Timer {
        id: autoDismissTimer

        interval: 50
        running: !appGrid.searchGestureActive && appGrid.searchPullProgress > 0.01 && appGrid.searchPullProgress < 0.99 && !UIStore.searchOpen
        repeat: false
        onTriggered: {
            appGrid.searchPullProgress = 0;
        }
    }

    Connections {
        function onSearchOpenChanged() {
            if (!UIStore.searchOpen && !appGrid.searchGestureActive)
                appGrid.searchPullProgress = 0;
        }

        target: UIStore
    }

    component IconCell: Item {
        id: iconCell

        required property int index
        readonly property var appData: appGrid.appModel ? appGrid.appModel.getAppAtIndex(appGrid.startIndex + index) : null
        // Read by IconOverlay to place this icon's decorations.
        readonly property Item contentColumn: contentColumn
        readonly property Item iconBox: iconBox
        readonly property bool removable: appGrid.editing && appData !== null && AppModel.canUninstall(appData.id)
        readonly property bool leaving: appData !== null && appGrid.removing[appData.id] !== undefined
        // 0 hidden and lowered, 1 in place.
        property real entrance: appGrid.entranceHeld ? 0 : 1

        function showInfo() {
            Tasks.launchAppWithRoute("settings", "appmanager/" + appData.id, JSON.stringify({
                "appId": appData.id
            }), null, null);
        }

        // The window grows out of this icon.
        function launch() {
            WindowOrigins.markLaunch(iconBox, false);
            appGrid.appLaunched(appData);
        }

        function playEntrance() {
            entranceAnim.restart();
        }

        // 0 on the home screen, 1 settled into its management tile: a wave
        // across the grid, then still.
        property real edit: 0

        SequentialAnimation {
            id: settle

            PauseAnimation {
                duration: MMotion.reduceMotion || !appGrid.editing ? 0 : iconCell.index * MMotion.staggerMicro
            }
            NumberAnimation {
                target: iconCell
                property: "edit"
                to: appGrid.editing ? 1 : 0
                duration: MMotion.reduceMotion ? 0 : MMotion.durationFor("modal")
                easing.type: appGrid.editing ? Easing.OutBack : Easing.OutCubic
            }
        }

        Connections {
            function onEditingChanged() {
                settle.restart();
            }

            target: appGrid
        }
        // Made while managing (the grid rebuilt after an uninstall): settled.
        Component.onCompleted: if (appGrid.editing)
            edit = 1

        objectName: "appIcon-" + index
        width: iconGrid.width / appGrid.columns
        height: (iconGrid.height - (appGrid.rows - 1) * iconGrid.rowSpacing) / appGrid.rows

        Accessible.role: Accessible.Button
        Accessible.name: appData ? appData.name : ""
        Accessible.description: appGrid.editing ? qsTr("Opens app info") : ""
        Accessible.ignored: !appData
        Accessible.onPressAction: if (appData)
            appGrid.editing ? iconCell.showInfo() : iconCell.launch()

        // Staggered entrance — every home grid icon fades up in a
        // light wave on first paint. Index-based delay means the
        // top-left icon arrives first, the rest cascade. The cost
        // is one ParallelAnimation per cell that runs ONCE then
        // never again; cells reused on page change keep their
        // already-played state.
        MEntrance {
            target: iconCell
            index: iconCell.index
            stagger: MMotion.staggerMicro
        }

        SequentialAnimation {
            id: entranceAnim

            PropertyAction {
                target: iconCell
                property: "entrance"
                value: 0
            }
            PauseAnimation {
                duration: MMotion.reduceMotion ? 0 : iconCell.index * MMotion.staggerHome
            }
            NumberAnimation {
                target: iconCell
                property: "entrance"
                to: 1
                duration: MMotion.durationFor("entrance")
                easing.type: Easing.OutCubic
            }
        }

        // The management tile, under the icon and its label.
        Rectangle {
            visible: iconCell.edit > 0 && iconCell.appData !== null
            opacity: iconCell.leaving ? 0 : iconCell.edit
            anchors.centerIn: contentColumn
            width: Math.min(iconCell.width - Silica.Theme.paddingSmall, contentColumn.width + 2 * Silica.Theme.paddingMedium)
            height: contentColumn.height + 2 * Silica.Theme.paddingMedium
            radius: Silica.Theme.paddingLarge
            color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.08)
            border.width: 1
            border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.14)
            scale: 0.9 + 0.1 * Math.min(iconCell.edit, 1)
        }

        // Press feedback scales and lifts this column, not the cell:
        // a transform list on every cell (even at scale 1) gives
        // each icon a non-translate matrix, which stops Qt Quick
        // merging the antialiased shapes and labels across icons
        // (126 draw calls per frame on the home screen). The
        // scale property at 1.0 leaves the matrix translate-only.
        // The cell itself is left to MEntrance, which writes its
        // scale and y.
        Column {
            id: contentColumn

            anchors.centerIn: parent
            anchors.verticalCenterOffset: (iconMouseArea.pressShown ? -2 : 0) + (1 - iconCell.entrance) * (MMotion.reduceMotion ? 0 : Silica.Theme.paddingLarge)
            scale: iconCell.leaving ? 0.2 : (iconMouseArea.pressShown ? 0.95 : 1) - 0.1 * iconCell.edit
            opacity: iconCell.leaving ? 0 : iconCell.entrance

            Behavior on opacity {
                enabled: Constants.enableAnimations && !entranceAnim.running

                NumberAnimation {
                    duration: MMotion.durationFor("nav")
                    easing.type: Easing.InCubic
                }
            }

            Behavior on scale {
                enabled: Constants.enableAnimations

                NumberAnimation {
                    duration: MMotion.durationFor("microPress")
                    easing.type: MMotion.easingFor("microPress")
                }
            }

            Behavior on anchors.verticalCenterOffset {
                enabled: Constants.enableAnimations && !entranceAnim.running

                NumberAnimation {
                    duration: MMotion.durationFor("microPress")
                    easing.type: MMotion.easingFor("microPress")
                }
            }

            spacing: Math.round(10 * (Constants.scaleFactor || 1.0))

            Item {
                id: iconBox

                anchors.horizontalCenter: parent.horizontalCenter
                width: Silica.Theme.iconSizeLauncher
                height: Silica.Theme.iconSizeLauncher

                // Pressed: the icon itself dims.
                MAppIcon {
                    id: appIcon

                    source: iconCell.appData ? iconCell.appData.icon : ""
                    size: parent.width
                    anchors.centerIn: parent
                    opacity: iconMouseArea.pressShown ? Silica.Theme.opacityHigh : 1
                }
            }

            // Silica's launcher label size.
            Text {
                id: label

                objectName: "appLabel"
                width: iconCell.width - Silica.Theme.paddingSmall
                horizontalAlignment: Text.AlignHCenter
                text: iconCell.appData ? iconCell.appData.name : ""
                color: tone.glyph
                style: Text.Outline
                styleColor: tone.halo
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeTiny
                // Names longer than the column wrap to a second line at word
                // boundaries; one long word elides rather than splitting.
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 2
            }
        }

        // The label's own strip of wallpaper, from the gap under the icon.
        WallpaperTone {
            id: tone

            objectName: "labelTone"
            x: contentColumn.x + label.x + (label.width - label.contentWidth) / 2
            y: contentColumn.y + label.y - contentColumn.spacing / 2
            width: label.contentWidth
            height: label.height + contentColumn.spacing
        }

        MouseArea {
            id: iconMouseArea

            readonly property bool pressShown: pressed && !tapTimeout.running

            Timer {
                id: tapTimeout

                interval: MMotion.tapTimeout
                running: iconMouseArea.pressed
            }

            property real pressX: 0
            property real pressY: 0
            property real pressTime: 0
            property bool isSearchGesture: false
            property bool held: false
            property real dragDistance: 0
            readonly property real pullThreshold: 100
            readonly property real commitThreshold: 0.35

            anchors.fill: parent
            z: 200
            preventStealing: false
            onPressed: mouse => {
                pressX = mouse.x;
                pressY = mouse.y;
                pressTime = Date.now();
                isSearchGesture = false;
                held = false;
                dragDistance = 0;
                appGrid.searchGestureActive = false;
            }
            onPositionChanged: mouse => {
                var deltaX = Math.abs(mouse.x - pressX);
                var deltaY = mouse.y - pressY;
                dragDistance = deltaY;
                if (!isSearchGesture && deltaY > 10) {
                    if (Math.abs(deltaY) > Math.abs(deltaX) * 3 && deltaY > 0)
                        isSearchGesture = true;
                }
                if (isSearchGesture && deltaY > 0) {
                    appGrid.searchGestureActive = true;
                    appGrid.searchPullProgress = Math.min(1, deltaY / pullThreshold);
                }
            }
            onReleased: mouse => {
                appGrid.searchGestureActive = false;
                var deltaTime = Date.now() - pressTime;
                var velocity = dragDistance / deltaTime;
                if (isSearchGesture && (appGrid.searchPullProgress > commitThreshold || velocity > 0.25)) {
                    UIStore.openSearch();
                    appGrid.searchPullProgress = 0;
                    isSearchGesture = false;
                    return;
                }
                // A tap: a swipe the pager did not take still moved the finger.
                if (!isSearchGesture && !held && Math.abs(dragDistance) < 15 && Math.abs(mouse.x - pressX) < 15) {
                    if (iconCell.appData && appGrid.editing) {
                        iconCell.showInfo();
                        HapticManager.light();
                    } else if (iconCell.appData) {
                        iconCell.launch();
                        HapticManager.medium();
                    }
                }
                isSearchGesture = false;
            }
            onPressAndHold: {
                held = true;
                if (iconCell.appData && !appGrid.editing) {
                    appGrid.editRequested();
                    HapticManager.medium();
                }
            }
        }
    }

    // Decorations live in per-kind layers so each layer batches; IconOverlay
    // tracks its cell's position, entrance and press transforms.
    component IconOverlay: Item {
        id: overlay

        property int cellIndex: -1
        readonly property IconCell cell: cellIndex >= 0 && iconRepeater.count > cellIndex ? iconRepeater.itemAt(cellIndex) as IconCell : null
        default property alias content: iconArea.data

        x: cell ? cell.x : 0
        y: cell ? cell.y : 0
        width: cell ? cell.width : 0
        height: cell ? cell.height : 0
        scale: cell ? cell.scale : 1
        opacity: cell ? cell.opacity : 0
        visible: cell !== null

        Item {
            x: overlay.cell ? overlay.cell.contentColumn.x : 0
            y: overlay.cell ? overlay.cell.contentColumn.y : 0
            width: overlay.cell ? overlay.cell.contentColumn.width : 0
            height: overlay.cell ? overlay.cell.contentColumn.height : 0
            scale: overlay.cell ? overlay.cell.contentColumn.scale : 1
            opacity: overlay.cell ? overlay.cell.contentColumn.opacity : 1

            Item {
                id: iconArea

                x: overlay.cell ? overlay.cell.iconBox.x : 0
                width: Silica.Theme.iconSizeLauncher
                height: Silica.Theme.iconSizeLauncher
            }
        }
    }

    Grid {
        id: iconGrid

        anchors.fill: parent
        anchors.topMargin: 10
        // The page margin every app and the dock use, so the outer columns
        // line up with the rest of the UI instead of running to the edges.
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        anchors.bottomMargin: Constants.bottomBarHeight + 12
        columns: appGrid.columns
        rows: appGrid.rows
        // Labels take the whole column pitch; the icons are narrower anyway.
        columnSpacing: 0
        rowSpacing: Math.round(8 * (Constants.scaleFactor || 1.0))

        Repeater {
            id: iconRepeater

            model: appGrid.pageItemCount

            IconCell {}
        }
    }

    // Notification badge — tealBright per DS Badges spec
    // (ds-components.jsx). Marathon DS uses teal-on-black for counts; the
    // previous red was off-brand. The 2 px black ring sits the badge off
    // the icon edge cleanly.
    Item {
        anchors.fill: iconGrid

        Repeater {
            model: appGrid.badges

            IconOverlay {
                id: badgeOverlay

                required property var modelData

                cellIndex: modelData.index

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -4
                    anchors.rightMargin: -4
                    height: badgeLabel.font.pixelSize + 8
                    width: Math.max(height, badgeLabel.implicitWidth + 10)
                    radius: height / 2
                    color: MColors.marathonTealBright
                    border.width: 2
                    border.color: MColors.elev0

                    Text {
                        id: badgeLabel

                        text: badgeOverlay.modelData.count > 9 ? "9+" : badgeOverlay.modelData.count.toString()
                        color: MColors.textOnAccent
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: MTypography.weightDemiBold
                        font.features: ({
                                "tnum": 1
                            })
                        anchors.centerIn: parent
                    }
                }
            }
        }
    }

    // Management: an ✕ on each icon that can go.
    Item {
        anchors.fill: iconGrid

        Repeater {
            model: appGrid.editing ? appGrid.pageItemCount : 0

            IconOverlay {
                id: removeOverlay

                required property int index

                cellIndex: index

                Item {
                    readonly property IconCell cell: removeOverlay.cell

                    objectName: "removeApp-" + removeOverlay.index
                    visible: cell !== null && cell.removable && !cell.leaving
                    // A finger-sized target around a small mark on the corner.
                    width: Math.round(Silica.Theme.iconSizeMedium * 0.9)
                    height: width
                    x: -width / 2 + Silica.Theme.paddingSmall
                    y: -height / 2 + Silica.Theme.paddingSmall
                    scale: cell ? Math.max(0, cell.edit) : 0

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(Silica.Theme.iconSizeSmall * 0.85)
                        height: width
                        radius: width / 2
                        color: removeArea.pressed ? Silica.Theme.rgba(Silica.Theme.primaryColor, 0.7) : Silica.Theme.primaryColor

                        GlyphIcon {
                            anchors.centerIn: parent
                            name: "x"
                            size: Math.round(parent.width * 0.62)
                            color: MColors.textOnAccent
                        }
                    }

                    MouseArea {
                        id: removeArea

                        anchors.fill: parent
                        onClicked: {
                            HapticManager.light();
                            confirmCard.open(parent.cell);
                        }
                    }

                    Accessible.role: Accessible.Button
                    Accessible.name: cell && cell.appData ? qsTr("Uninstall %1").arg(cell.appData.name) : ""
                    Accessible.ignored: !visible
                    Accessible.onPressAction: confirmCard.open(cell)
                }
            }
        }
    }

    // The ✕'s question, asked in place beside the icon: the grid stays in view.
    Item {
        id: confirmCard

        property bool shown: false
        property Item cell: null
        readonly property var app: cell ? cell.appData : null
        readonly property real cellY: cell ? cell.mapToItem(confirmCard, 0, 0).y : 0
        readonly property string kind: !app ? "" : app.id.indexOf("deckard.") === 0 ? qsTr("Android app") : app.type === "flatpak" ? qsTr("Flatpak app") : qsTr("Marathon app")

        function open(target) {
            cell = target;
            shown = true;
        }

        function close() {
            shown = false;
        }

        anchors.fill: parent
        z: 300
        visible: card.opacity > 0

        Connections {
            function onEditingChanged() {
                confirmCard.close();
            }

            target: appGrid
        }

        // A tap anywhere else keeps the app.
        MouseArea {
            anchors.fill: parent
            enabled: confirmCard.shown
            onClicked: confirmCard.close()
        }

        Rectangle {
            id: card

            readonly property bool below: confirmCard.cellY + (confirmCard.cell ? confirmCard.cell.height : 0) + height + Silica.Theme.paddingSmall <= confirmCard.height

            x: Silica.Theme.horizontalPageMargin
            y: below ? confirmCard.cellY + (confirmCard.cell ? confirmCard.cell.height : 0) + Silica.Theme.paddingSmall : confirmCard.cellY - height - Silica.Theme.paddingSmall
            width: confirmCard.width - 2 * Silica.Theme.horizontalPageMargin
            height: content.height + 2 * Silica.Theme.paddingLarge
            radius: Silica.Theme.paddingLarge
            color: MColors.elev2
            border.width: 1
            border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.14)
            opacity: confirmCard.shown ? 1 : 0
            scale: confirmCard.shown ? 1 : 0.94
            transformOrigin: below ? Item.Top : Item.Bottom

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.reduceMotion ? 0 : MMotion.durationFor("modal")
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: MMotion.reduceMotion ? 0 : MMotion.durationFor("modal")
                    easing.type: Easing.OutBack
                }
            }

            MouseArea {
                anchors.fill: parent
            }

            Column {
                id: content

                x: Silica.Theme.paddingLarge
                y: Silica.Theme.paddingLarge
                width: parent.width - 2 * Silica.Theme.paddingLarge
                spacing: Silica.Theme.paddingLarge

                Row {
                    width: parent.width
                    spacing: Silica.Theme.paddingMedium

                    MAppIcon {
                        source: confirmCard.app ? confirmCard.app.icon : ""
                        size: Silica.Theme.iconSizeMedium
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - Silica.Theme.iconSizeMedium - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            width: parent.width
                            text: confirmCard.app ? qsTr("Uninstall %1?").arg(confirmCard.app.name) : ""
                            color: Silica.Theme.primaryColor
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightDemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: qsTr("%1 · its data goes with it").arg(confirmCard.kind)
                            color: Silica.Theme.secondaryColor
                            font.family: MTypography.fontFamily
                            font.pixelSize: Silica.Theme.fontSizeExtraSmall
                            elide: Text.ElideRight
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: Silica.Theme.paddingMedium

                    CardButton {
                        text: qsTr("Keep")
                        onActivated: confirmCard.close()
                    }

                    CardButton {
                        objectName: "confirmUninstall"
                        text: qsTr("Uninstall")
                        destructive: true
                        onActivated: {
                            const app = confirmCard.app;
                            confirmCard.close();
                            appGrid.uninstallConfirmed(app);
                        }
                    }
                }
            }

            Accessible.role: Accessible.Dialog
            Accessible.name: confirmCard.app ? qsTr("Uninstall %1?").arg(confirmCard.app.name) : ""
        }
    }

    component CardButton: Rectangle {
        id: button

        property alias text: buttonLabel.text
        property bool destructive: false
        signal activated

        width: buttonLabel.implicitWidth + 2 * Silica.Theme.paddingLarge
        height: Silica.Theme.itemSizeExtraSmall
        radius: height / 2
        color: destructive ? Silica.Theme.rgba(MColors.error, buttonArea.pressed ? 0.35 : 0.2) : Silica.Theme.rgba(Silica.Theme.primaryColor, buttonArea.pressed ? 0.16 : 0.08)

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            color: button.destructive ? MColors.error : Silica.Theme.primaryColor
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeBody
            font.weight: MTypography.weightDemiBold
        }

        MouseArea {
            id: buttonArea

            anchors.fill: parent
            onClicked: {
                HapticManager.light();
                button.activated();
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: buttonLabel.text
        Accessible.onPressAction: button.activated()
    }

    // Management ends on a tap off the icons; the wallpaper dims under them.
    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: appGrid.editing
        onClicked: appGrid.editDone()

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: appGrid.editing ? 0.28 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: MMotion.reduceMotion ? 0 : MMotion.durationFor("modal")
                }
            }
        }
    }

    MouseArea {
        id: gestureMask

        property real pressX: 0
        property real pressY: 0
        property bool isDownwardSwipe: false
        property real dragDistance: 0
        readonly property real pullThreshold: 100

        anchors.fill: parent
        z: 100
        enabled: !UIStore.searchOpen
        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            isDownwardSwipe = false;
            mouse.accepted = false;
        }
        onPositionChanged: mouse => {
            var deltaX = Math.abs(mouse.x - pressX);
            var deltaY = mouse.y - pressY;
            dragDistance = deltaY;
            if (!isDownwardSwipe && deltaY > 10) {
                if (Math.abs(deltaY) > Math.abs(deltaX) * 3 && deltaY > 0) {
                    isDownwardSwipe = true;
                    mouse.accepted = true;
                } else {
                    mouse.accepted = false;
                    return;
                }
            }
            if (isDownwardSwipe && deltaY > 0) {
                appGrid.searchGestureActive = true;
                appGrid.searchPullProgress = Math.min(1, deltaY / pullThreshold);
                mouse.accepted = true;
            }
        }
        onReleased: mouse => {
            if (isDownwardSwipe) {
                appGrid.searchGestureActive = false;
                if (appGrid.searchPullProgress > 0.35) {
                    UIStore.openSearch();
                    appGrid.searchPullProgress = 0;
                }
                mouse.accepted = true;
            }
            isDownwardSwipe = false;
        }
    }

    Behavior on searchPullProgress {
        enabled: !appGrid.searchGestureActive && appGrid.searchPullProgress > 0.01 && !UIStore.searchOpen

        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
            onRunningChanged: {
                if (!running && appGrid.searchPullProgress < 0.02)
                    appGrid.searchPullProgress = 0;
            }
        }
    }
}
