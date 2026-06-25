import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: bottomBar

    property int currentPage: 0
    property int totalPages: 1
    property bool showNotifications: currentPage >= 0
    property bool showPageIndicators: true

    signal appLaunched(var app)
    signal pageNavigationRequested(int page)

    height: Constants.bottomBarHeight
    Component.onCompleted: Logger.info("BottomBar", "Initialized")

    // ── Glass tabbar background ───────────────────────────────
    // DS spec (ds-components.jsx Bars · 70 px tab bar): a glass
    // tint with a hairline top divider. Until backdrop-blur is
    // wired through MultiEffect, the rgba glassTabbar alone gives
    // the right composition over the wallpaper aurora.
    Rectangle {
        id: background

        anchors.fill: parent
        color: MColors.glassTabbar
        z: Constants.zIndexBackground
    }

    // Hairline divider above the tab bar.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: MColors.borderGlass
        z: Constants.zIndexBackground + 1
    }

    Item {
        id: phoneShortcut

        anchors.left: parent.left
        // Tightened from spacingLarge — at scaleFactor 2 the Phone glyph
        // floats 40 px in from the panel edge, breaking the iOS-like
        // edge-hugging shortcut feel.
        anchors.leftMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 10

        Image {
            source: "qrc:/images/phone.svg"
            width: Constants.iconSizeMedium
            height: Constants.iconSizeMedium
            sourceSize.width: Constants.iconSizeMedium
            sourceSize.height: Constants.iconSizeMedium
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
            asynchronous: true
            cache: true
            opacity: phoneMouseArea.pressed ? 0.6 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            id: phoneMouseArea

            property real startY: 0

            anchors.fill: parent
            propagateComposedEvents: true
            preventStealing: false
            onPressed: mouse => {
                startY = mouse.y;
            }
            onReleased: mouse => {
                const deltaY = Math.abs(mouse.y - startY);
                if (deltaY < 10) {
                    var app = {
                        "id": "phone",
                        "name": "Phone",
                        "icon": "phone"
                    };
                    appLaunched(app);
                } else {
                    mouse.accepted = false;
                }
            }
        }
    }

    Row {
        id: pageIndicatorRow

        anchors.centerIn: parent
        anchors.verticalCenterOffset: 0
        spacing: Constants.spacingMedium
        z: 1
        visible: bottomBar.showPageIndicators

        Rectangle {
            id: hubIndicator

            readonly property bool isActive: bottomBar.currentPage === -2

            width: isActive ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: isActive ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: 999
            color: isActive ? MColors.textPrimary : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                name: "inbox"
                size: hubIndicator.isActive ? Constants.iconSizeSmall : Constants.fontSizeSmall
                anchors.centerIn: parent
                color: hubIndicator.isActive ? MColors.elev0 : MColors.textPrimary
                visible: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bottomBar.pageNavigationRequested(-2)
            }

            Behavior on width {
                NumberAnimation {
                    duration: 200
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: 200
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }

        // Frames (Active Frames task switcher) page indicator. Lights up
        // when on the task-switcher page; tap navigates there.
        Rectangle {
            id: framesIndicator

            readonly property bool isActive: bottomBar.currentPage === -1

            width: isActive ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: isActive ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: 999
            color: isActive ? MColors.textPrimary : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                name: "layers"
                size: framesIndicator.isActive ? Constants.iconSizeSmall : Constants.fontSizeSmall
                anchors.centerIn: parent
                color: framesIndicator.isActive ? MColors.elev0 : MColors.textPrimary
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bottomBar.pageNavigationRequested(-1)
            }

            Behavior on width {
                NumberAnimation {
                    duration: 200
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: 200
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }

        Repeater {
            id: appGridIndicators

            model: bottomBar.totalPages

            Rectangle {
                id: pageIndicator

                required property int index
                property int pageIndex: index

                width: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                height: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                radius: 999
                color: index === bottomBar.currentPage ? MColors.textPrimary : MColors.textTertiary
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: (pageIndicator.pageIndex + 1).toString()
                    color: MColors.elev0
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.weight: MTypography.weightDemiBold
                    font.features: ({
                            "tnum": 1
                        })
                    anchors.centerIn: parent
                    visible: pageIndicator.pageIndex === bottomBar.currentPage
                    opacity: visible ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: bottomBar.pageNavigationRequested(pageIndicator.pageIndex)
                }

                Behavior on width {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Behavior on height {
                    NumberAnimation {
                        duration: 200
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
            }
        }
    }

    MouseArea {
        id: scrubGesture

        property bool isDragging: false
        property int lastHoveredPage: -999

        function checkPageUnderMouse(mouseX, mouseY) {
            var hubPos = mapToItem(hubIndicator, mouseX, mouseY);
            if (hubPos.x >= 0 && hubPos.x <= hubIndicator.width && hubPos.y >= 0 && hubPos.y <= hubIndicator.height) {
                if (lastHoveredPage !== -2) {
                    lastHoveredPage = -2;
                    bottomBar.pageNavigationRequested(-2);
                }
                return;
            }
            var framesPos = mapToItem(framesIndicator, mouseX, mouseY);
            if (framesPos.x >= 0 && framesPos.x <= framesIndicator.width && framesPos.y >= 0 && framesPos.y <= framesIndicator.height) {
                if (lastHoveredPage !== -1) {
                    lastHoveredPage = -1;
                    bottomBar.pageNavigationRequested(-1);
                }
                return;
            }
            for (var i = 0; i < appGridIndicators.count; i++) {
                var indicator = appGridIndicators.itemAt(i);
                if (indicator) {
                    var indicatorPos = mapToItem(indicator, mouseX, mouseY);
                    if (indicatorPos.x >= 0 && indicatorPos.x <= indicator.width && indicatorPos.y >= 0 && indicatorPos.y <= indicator.height) {
                        if (lastHoveredPage !== i) {
                            lastHoveredPage = i;
                            bottomBar.pageNavigationRequested(i);
                        }
                        return;
                    }
                }
            }
        }

        anchors.fill: pageIndicatorRow
        anchors.margins: -Constants.spacingSmall
        z: 2
        preventStealing: false
        propagateComposedEvents: false
        onPressed: mouse => {
            isDragging = true;
            lastHoveredPage = -999;
            checkPageUnderMouse(mouse.x, mouse.y);
        }
        onPositionChanged: mouse => {
            if (isDragging)
                checkPageUnderMouse(mouse.x, mouse.y);
        }
        onReleased: {
            isDragging = false;
            lastHoveredPage = -999;
        }
        onCanceled: {
            isDragging = false;
            lastHoveredPage = -999;
        }
    }

    Item {
        id: cameraShortcut

        anchors.right: parent.right
        // Symmetric with phoneShortcut.leftMargin tightening.
        anchors.rightMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 10

        Image {
            source: "qrc:/images/camera.svg"
            width: Constants.iconSizeMedium
            height: Constants.iconSizeMedium
            sourceSize.width: Constants.iconSizeMedium
            sourceSize.height: Constants.iconSizeMedium
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            anchors.centerIn: parent
            opacity: cameraMouseArea.pressed ? 0.6 : 1

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            id: cameraMouseArea

            property real startY: 0

            anchors.fill: parent
            propagateComposedEvents: true
            preventStealing: false
            onPressed: mouse => {
                startY = mouse.y;
            }
            onReleased: mouse => {
                const deltaY = Math.abs(mouse.y - startY);
                if (deltaY < 10) {
                    var app = {
                        "id": "camera",
                        "name": "Camera",
                        "icon": "qrc:/images/camera.svg"
                    };
                    appLaunched(app);
                } else {
                    mouse.accepted = false;
                }
            }
        }
    }
}
