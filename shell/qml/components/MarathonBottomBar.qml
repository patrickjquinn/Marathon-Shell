import QtQuick
import MarathonOS.Shell
import "."
import MarathonUI.Theme

Item {
    id: bottomBar
    height: Constants.bottomBarHeight

    property int currentPage: 0
    property int totalPages: 1
    property bool showNotifications: currentPage >= 0
    property bool showPageIndicators: true

    signal appLaunched(var app)
    signal pageNavigationRequested(int page)

    Component.onCompleted: Logger.info("BottomBar", "Initialized")

    Rectangle {
        id: background
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: WallpaperStore.isDark ? "#80000000" : "#80FFFFFF"
            }
        }
        z: Constants.zIndexBackground
    }

    Item {
        id: phoneShortcut
        anchors.left: parent.left
        anchors.leftMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 10

        Image {
            source: "qrc:/images/phone.svg"
            width: Constants.iconSizeMedium
            height: Constants.iconSizeMedium
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
            asynchronous: true
            cache: true
            opacity: phoneMouseArea.pressed ? 0.6 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            id: phoneMouseArea
            anchors.fill: parent
            propagateComposedEvents: true
            preventStealing: false

            property real startY: 0

            onPressed: mouse => {
                startY = mouse.y;
            }

            onReleased: mouse => {
                // Only trigger click if no significant vertical movement (not a swipe)
                const deltaY = Math.abs(mouse.y - startY);
                if (deltaY < 10) {
                    var app = {
                        id: "phone",
                        name: "Phone",
                        icon: "qrc:/images/phone.svg"
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
            width: bottomBar.currentPage === -2 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: bottomBar.currentPage === -2 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: 999  // BB10: True circle
            color: bottomBar.currentPage === -2 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter

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

            Image {
                source: bottomBar.currentPage === -2 ? "qrc:/images/icons/lucide/inbox-black.svg" : "qrc:/images/icons/lucide/inbox.svg"
                width: bottomBar.currentPage === -2 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                height: bottomBar.currentPage === -2 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
                smooth: true
                antialiasing: true

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
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bottomBar.pageNavigationRequested(-2)
            }
        }

        Rectangle {
            id: framesIndicator
            width: bottomBar.currentPage === -1 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: bottomBar.currentPage === -1 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: 999  // BB10: True circle
            color: bottomBar.currentPage === -1 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter

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

            Image {
                source: bottomBar.currentPage === -1 ? "qrc:/images/icons/lucide/grid-black.svg" : "qrc:/images/icons/lucide/grid.svg"
                width: bottomBar.currentPage === -1 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                height: bottomBar.currentPage === -1 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
                smooth: true
                antialiasing: true

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
            }

            MouseArea {
                anchors.fill: parent
                onClicked: bottomBar.pageNavigationRequested(-1)
            }
        }

        Repeater {
            id: appGridIndicators
            model: bottomBar.totalPages

            Rectangle {
                id: pageIndicator
                width: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                height: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                radius: 999  // BB10: True circle
                color: index === bottomBar.currentPage ? "#FFFFFF" : "#444444"
                anchors.verticalCenter: parent.verticalCenter

                property int pageIndex: index

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

                Text {
                    text: (pageIndicator.pageIndex + 1).toString()
                    color: "#000000"
                    font.pixelSize: Constants.fontSizeSmall
                    font.weight: Font.Medium
                    anchors.centerIn: parent
                    visible: pageIndicator.pageIndex === bottomBar.currentPage
                    opacity: visible ? 1.0 : 0.0

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
            }
        }
    }

    // Drag/scrub gesture handler
    MouseArea {
        id: scrubGesture
        anchors.fill: pageIndicatorRow
        anchors.margins: -Constants.spacingSmall
        z: 2
        preventStealing: false
        propagateComposedEvents: false

        property bool isDragging: false
        property int lastHoveredPage: -999

        onPressed: mouse => {
            isDragging = true;
            lastHoveredPage = -999;
            checkPageUnderMouse(mouse.x, mouse.y);
        }

        onPositionChanged: mouse => {
            if (isDragging) {
                checkPageUnderMouse(mouse.x, mouse.y);
            }
        }

        onReleased: {
            isDragging = false;
            lastHoveredPage = -999;
        }

        onCanceled: {
            isDragging = false;
            lastHoveredPage = -999;
        }

        function checkPageUnderMouse(mouseX, mouseY) {
            // Check Hub indicator
            var hubPos = mapToItem(hubIndicator, mouseX, mouseY);
            if (hubPos.x >= 0 && hubPos.x <= hubIndicator.width && hubPos.y >= 0 && hubPos.y <= hubIndicator.height) {
                if (lastHoveredPage !== -2) {
                    lastHoveredPage = -2;
                    bottomBar.pageNavigationRequested(-2);
                }
                return;
            }

            // Check Frames indicator
            var framesPos = mapToItem(framesIndicator, mouseX, mouseY);
            if (framesPos.x >= 0 && framesPos.x <= framesIndicator.width && framesPos.y >= 0 && framesPos.y <= framesIndicator.height) {
                if (lastHoveredPage !== -1) {
                    lastHoveredPage = -1;
                    bottomBar.pageNavigationRequested(-1);
                }
                return;
            }

            // Check each app grid page indicator
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
    }

    Item {
        id: cameraShortcut
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 10

        Image {
            source: "qrc:/images/camera.svg"
            width: Constants.iconSizeMedium
            height: Constants.iconSizeMedium
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            anchors.centerIn: parent
            opacity: cameraMouseArea.pressed ? 0.6 : 1.0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            id: cameraMouseArea
            anchors.fill: parent
            propagateComposedEvents: true
            preventStealing: false

            property real startY: 0

            onPressed: mouse => {
                startY = mouse.y;
            }

            onReleased: mouse => {
                // Only trigger click if no significant vertical movement (not a swipe)
                const deltaY = Math.abs(mouse.y - startY);
                if (deltaY < 10) {
                    var app = {
                        id: "camera",
                        name: "Camera",
                        icon: "qrc:/images/camera.svg"
                    };
                    appLaunched(app);
                } else {
                    mouse.accepted = false;
                }
            }
        }
    }
}
