pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

// The home dock: Phone and Camera either side of the page indicator, on the
// wallpaper fading to black.
Item {
    id: bottomBar

    property int currentPage: 0
    property int totalPages: 1
    property bool showNotifications: currentPage >= 0
    property bool showPageIndicators: true

    signal appLaunched(var app)
    signal pageNavigationRequested(int page)

    // The lock screen's glass-ring shortcut, launching on a tap and
    // ignoring a vertical drag through to the gestures beneath.
    component DockButton: MCircularIconButton {
        id: dockButton

        property var app

        width: Silica.Theme.itemSizeSmall
        height: width
        anchors.verticalCenter: parent.verticalCenter
        z: 10
        iconSize: Silica.Theme.iconSizeSmall
        variant: "secondary"
        a11yName: app.name
        down: mouse.pressed
        onClicked: bottomBar.appLaunched(app)

        MouseArea {
            id: mouse

            property real startY: 0

            anchors.fill: parent
            propagateComposedEvents: true
            onPressed: event => startY = event.y
            onReleased: event => {
                if (Math.abs(event.y - startY) < 10)
                    bottomBar.appLaunched(dockButton.app);
                else
                    event.accepted = false;
            }
        }
    }

    component PageGlyph: Item {
        id: glyph

        property string iconName
        property string a11yName
        property bool active: false

        signal clicked

        width: Silica.Theme.itemSizeExtraSmall
        height: width
        anchors.verticalCenter: parent.verticalCenter

        Accessible.role: Accessible.Button
        Accessible.name: a11yName
        Accessible.onPressAction: clicked()

        GlyphIcon {
            anchors.centerIn: parent
            name: glyph.iconName
            size: glyph.active ? Silica.Theme.iconSizeSmall : Math.round(Silica.Theme.iconSizeSmall * 0.75)
            color: glyph.active ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
        }

        MouseArea {
            anchors.fill: parent
            onClicked: glyph.clicked()
        }
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
        anchors.left: parent.left
        anchors.leftMargin: Silica.Theme.horizontalPageMargin
        iconName: "phone"
        app: ({
                "id": "phone",
                "name": "Phone",
                "icon": "phone"
            })
    }

    Row {
        id: pageIndicatorRow

        anchors.centerIn: parent
        spacing: Silica.Theme.paddingMedium
        z: 1
        visible: bottomBar.showPageIndicators

        PageGlyph {
            id: hubIndicator

            iconName: "inbox"
            a11yName: qsTr("Hub")
            active: bottomBar.currentPage === -2
            onClicked: bottomBar.pageNavigationRequested(-2)
        }

        PageGlyph {
            id: framesIndicator

            iconName: "layers"
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
                    NumberAnimation { duration: MMotion.quick }
                }
            }
        }
    }

    // Drag across the indicator to scrub between pages.
    MouseArea {
        id: scrubGesture

        property int lastHoveredPage: -999

        function pageAt(x, y) {
            for (const [item, page] of [[hubIndicator, -2], [framesIndicator, -1]]) {
                const p = mapToItem(item, x, y);
                if (p.x >= 0 && p.x <= item.width && p.y >= 0 && p.y <= item.height)
                    return page;
            }
            for (let i = 0; i < appGridIndicators.count; i++) {
                const item = appGridIndicators.itemAt(i);
                const p = mapToItem(item, x, y);
                if (p.x >= -Silica.Theme.paddingSmall && p.x <= item.width + Silica.Theme.paddingSmall)
                    return i;
            }
            return -999;
        }

        function scrubTo(x, y) {
            const page = pageAt(x, y);
            if (page !== -999 && page !== lastHoveredPage) {
                lastHoveredPage = page;
                bottomBar.pageNavigationRequested(page);
            }
        }

        anchors.fill: pageIndicatorRow
        anchors.margins: -Silica.Theme.paddingMedium
        z: 2
        onPressed: event => {
            lastHoveredPage = -999;
            scrubTo(event.x, event.y);
        }
        onPositionChanged: event => scrubTo(event.x, event.y)
        onReleased: lastHoveredPage = -999
        onCanceled: lastHoveredPage = -999
    }

    DockButton {
        anchors.right: parent.right
        anchors.rightMargin: Silica.Theme.horizontalPageMargin
        iconName: "camera"
        app: ({
                "id": "camera",
                "name": "Camera",
                "icon": "qrc:/images/camera.svg"
            })
    }
}
