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

    Rectangle {
        id: background

        anchors.fill: parent
        z: Constants.zIndexBackground

        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }

            GradientStop {
                position: 1
                color: WallpaperStore.isDark ? "#80000000" : "#80FFFFFF"
            }
        }
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

            width: bottomBar.currentPage === -2 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: bottomBar.currentPage === -2 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: 999
            color: bottomBar.currentPage === -2 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                name: "inbox"
                size: bottomBar.currentPage === -2 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                anchors.centerIn: parent
                color: bottomBar.currentPage === -2 ? "black" : "white"
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

        Rectangle {
            id: framesIndicator

            width: bottomBar.currentPage === -1 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            height: bottomBar.currentPage === -1 ? Constants.pageIndicatorHubSizeActive : Constants.pageIndicatorHubSizeInactive
            radius: 999
            color: bottomBar.currentPage === -1 ? "#FFFFFF" : "transparent"
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                name: "layers"
                size: bottomBar.currentPage === -1 ? Constants.iconSizeSmall : Constants.fontSizeSmall
                anchors.centerIn: parent
                color: bottomBar.currentPage === -1 ? "black" : "white"
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

                property int pageIndex: index

                width: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                height: index === bottomBar.currentPage ? Constants.pageIndicatorSizeActive : Constants.pageIndicatorSizeInactive
                radius: 999
                color: index === bottomBar.currentPage ? "#FFFFFF" : "#444444"
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: (pageIndicator.pageIndex + 1).toString()
                    color: "#000000"
                    font.pixelSize: Constants.fontSizeSmall
                    font.weight: Font.Medium
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
