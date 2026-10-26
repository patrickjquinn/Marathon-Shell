pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// The home dock: Phone and Camera either side of the page indicator, on the
// wallpaper fading to black. Bare glyphs, as Silica's IconButton; the touch
// areas are padded, not drawn.
Item {
    id: bottomBar

    property int currentPage: 0
    property int totalPages: 1
    property bool showNotifications: currentPage >= 0
    property bool showPageIndicators: true

    // The row sits a clear gap above the nav bar, and its touch areas
    // never reach into it.
    readonly property real rowCenter: Math.min((height - Silica.Theme.paddingMedium) / 2, height - Silica.Theme.itemSizeExtraSmall / 2)

    signal appLaunched(var app)
    signal pageNavigationRequested(int page)

    // Launches on a tap and lets a vertical drag through to the gestures
    // beneath.
    component DockButton: MouseArea {
        id: dockButton

        property var app
        property string iconName
        property real startY: 0

        width: Silica.Theme.itemSizeExtraSmall
        height: width
        y: bottomBar.rowCenter - height / 2
        z: 10
        propagateComposedEvents: true
        Accessible.role: Accessible.Button
        Accessible.name: app.name
        Accessible.onPressAction: bottomBar.appLaunched(app)
        onPressed: event => startY = event.y
        onReleased: event => {
            if (Math.abs(event.y - startY) < Silica.Theme.startDragDistance)
                bottomBar.appLaunched(dockButton.app);
            else
                event.accepted = false;
        }

        GlyphIcon {
            anchors.centerIn: parent
            name: dockButton.iconName
            size: Silica.Theme.iconSizeSmall
            color: dockButton.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
        }
    }

    component PageGlyph: GlyphIcon {
        property string a11yName
        property bool active: false

        signal clicked

        anchors.verticalCenter: parent.verticalCenter
        size: Silica.Theme.iconSizeExtraSmall
        color: active ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
        Accessible.ignored: false
        Accessible.role: Accessible.Button
        Accessible.name: a11yName
        Accessible.onPressAction: clicked()
    }

    height: Constants.bottomBarHeight

    Rectangle {
        anchors.fill: parent
        z: Constants.zIndexBackground
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: Qt.rgba(0, 0, 0, 0.6)
            }
        }
    }

    DockButton {
        objectName: "dockPhone"
        // Glyph flush with the page margin.
        x: Silica.Theme.horizontalPageMargin - (width - Silica.Theme.iconSizeSmall) / 2
        iconName: "phone"
        app: ({
                "id": "phone",
                "name": qsTr("Phone"),
                "icon": "phone"
            })
    }

    Row {
        id: pageIndicatorRow

        objectName: "pageIndicatorRow"
        anchors.horizontalCenter: parent.horizontalCenter
        y: bottomBar.rowCenter - height / 2
        spacing: Silica.Theme.paddingLarge
        z: 1
        visible: bottomBar.showPageIndicators

        PageGlyph {
            id: hubIndicator

            name: "inbox"
            a11yName: qsTr("Hub")
            active: bottomBar.currentPage === -2
            onClicked: bottomBar.pageNavigationRequested(-2)
        }

        PageGlyph {
            id: framesIndicator

            name: "layers"
            a11yName: qsTr("Open apps")
            active: bottomBar.currentPage === -1
            onClicked: bottomBar.pageNavigationRequested(-1)
        }

        Repeater {
            id: appGridIndicators

            model: bottomBar.totalPages

            Rectangle {
                id: pageIndicator

                required property int index
                readonly property bool active: index === bottomBar.currentPage

                anchors.verticalCenter: parent.verticalCenter
                width: active ? Silica.Theme.paddingLarge * 2 : Silica.Theme.paddingLarge
                height: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
                radius: height / 2
                color: active ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Page %1").arg(index + 1)

                Behavior on width {
                    NumberAnimation {
                        duration: MMotion.quick
                        easing.type: MMotion.easingFor("tap")
                    }
                }
            }
        }
    }

    // Tap an indicator, or drag across them to scrub between pages. The
    // nearest indicator wins, so the whole band is the touch area.
    MouseArea {
        id: scrubGesture

        property int lastHoveredPage: -999

        function pageAt(x) {
            const items = [[hubIndicator, -2], [framesIndicator, -1]];
            for (let i = 0; i < appGridIndicators.count; i++)
                items.push([appGridIndicators.itemAt(i), i]);
            let best = -999;
            let bestDistance = Infinity;
            for (const [item, page] of items) {
                const d = Math.abs(mapToItem(item, x, 0).x - item.width / 2);
                if (d < bestDistance) {
                    bestDistance = d;
                    best = page;
                }
            }
            return best;
        }

        function scrubTo(x) {
            const page = pageAt(x);
            if (page !== lastHoveredPage) {
                lastHoveredPage = page;
                bottomBar.pageNavigationRequested(page);
            }
        }

        objectName: "pageScrub"
        x: pageIndicatorRow.x - Silica.Theme.paddingMedium
        width: pageIndicatorRow.width + Silica.Theme.paddingMedium * 2
        height: Silica.Theme.itemSizeExtraSmall
        y: bottomBar.rowCenter - height / 2
        z: 2
        enabled: pageIndicatorRow.visible
        onPressed: event => {
            lastHoveredPage = -999;
            scrubTo(event.x);
        }
        onPositionChanged: event => scrubTo(event.x)
        onReleased: lastHoveredPage = -999
        onCanceled: lastHoveredPage = -999
    }

    DockButton {
        objectName: "dockCamera"
        x: bottomBar.width - Silica.Theme.horizontalPageMargin - Silica.Theme.iconSizeSmall - (width - Silica.Theme.iconSizeSmall) / 2
        iconName: "camera"
        app: ({
                "id": "camera",
                "name": qsTr("Camera"),
                "icon": "qrc:/images/camera.svg"
            })
    }
}
