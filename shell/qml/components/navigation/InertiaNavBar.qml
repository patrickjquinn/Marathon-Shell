import QtQuick

Rectangle {
    id: navBar

    property real dragStartX: 0
    property real dragStartY: 0
    property real dragCurrentX: 0
    property real dragCurrentY: 0
    property real dragVelocityX: 0
    property real dragVelocityY: 0
    property real lastDragTime: 0
    property real lastDragX: 0
    property real lastDragY: 0
    property bool isDragging: false
    property int swipeThreshold: 50
    property real snapDuration: 300
    property real maxDragDistance: 150

    signal swipeLeft
    signal swipeRight
    signal swipeUp
    signal swipeUpRelease(real velocity)

    height: Constants.navBarHeight
    color: "#000000"

    Rectangle {
        id: indicator

        anchors.centerIn: parent
        width: Constants.cardBannerHeight
        height: Constants.spacingXSmall
        radius: Constants.borderRadiusSmall
        color: "#FFFFFF"
        opacity: 0.8
        x: parent.width / 2 - width / 2 + (navBar.isDragging ? Math.max(-navBar.maxDragDistance, Math.min(navBar.maxDragDistance, navBar.dragCurrentX)) : 0)
        y: (navBar.isDragging && navBar.dragCurrentY < 0) ? Math.max(-60, navBar.dragCurrentY) : 0
        scale: navBar.isDragging ? 1.2 : 1

        Behavior on x {
            enabled: !navBar.isDragging

            SpringAnimation {
                spring: 3
                damping: 0.3
                duration: navBar.snapDuration
            }
        }

        Behavior on y {
            enabled: !navBar.isDragging

            SpringAnimation {
                spring: 3
                damping: 0.3
                duration: navBar.snapDuration
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }
    }

    Rectangle {
        id: dragHint

        anchors.centerIn: indicator
        width: indicator.width + 20
        height: indicator.height + 20
        radius: height / 2
        color: "#006666"
        opacity: navBar.isDragging ? 0.2 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }
    }

    MouseArea {
        id: navMouseArea

        anchors.fill: parent
        anchors.topMargin: -60
        onPressed: mouse => {
            navBar.dragStartX = mouse.x;
            navBar.dragStartY = mouse.y;
            navBar.lastDragX = mouse.x;
            navBar.lastDragY = mouse.y;
            navBar.dragCurrentX = 0;
            navBar.dragCurrentY = 0;
            navBar.dragVelocityX = 0;
            navBar.dragVelocityY = 0;
            navBar.lastDragTime = Date.now();
            navBar.isDragging = true;
            console.log(" Nav drag started at:", mouse.x, mouse.y);
        }
        onPositionChanged: mouse => {
            if (!navBar.isDragging)
                return;

            var now = Date.now();
            var deltaTime = now - navBar.lastDragTime;
            if (deltaTime > 0) {
                navBar.dragVelocityX = ((mouse.x - navBar.lastDragX) / deltaTime) * 1000;
                navBar.dragVelocityY = ((mouse.y - navBar.lastDragY) / deltaTime) * 1000;
            }
            navBar.dragCurrentX = mouse.x - navBar.dragStartX;
            navBar.dragCurrentY = mouse.y - navBar.dragStartY;
            navBar.lastDragX = mouse.x;
            navBar.lastDragY = mouse.y;
            navBar.lastDragTime = now;
            console.log(" Dragging:", navBar.dragCurrentX.toFixed(0), navBar.dragCurrentY.toFixed(0), "velocity:", navBar.dragVelocityX.toFixed(0), navBar.dragVelocityY.toFixed(0));
        }
        onReleased: mouse => {
            if (!navBar.isDragging)
                return;

            console.log(" Released. Distance:", navBar.dragCurrentX.toFixed(0), navBar.dragCurrentY.toFixed(0), "Velocity:", navBar.dragVelocityX.toFixed(0), navBar.dragVelocityY.toFixed(0));
            var absX = Math.abs(navBar.dragCurrentX);
            var absY = Math.abs(navBar.dragCurrentY);
            var absVelX = Math.abs(navBar.dragVelocityX);
            var absVelY = Math.abs(navBar.dragVelocityY);
            if (absY > absX) {
                if (navBar.dragCurrentY < -navBar.swipeThreshold || navBar.dragVelocityY < -500) {
                    console.log("⬆ SWIPE UP detected!");
                    swipeUp();
                    swipeUpRelease(Math.abs(navBar.dragVelocityY));
                }
            } else {
                if (navBar.dragCurrentX > navBar.swipeThreshold || navBar.dragVelocityX > 500) {
                    console.log("SWIPE RIGHT detected!");
                    swipeRight();
                } else if (navBar.dragCurrentX < -navBar.swipeThreshold || navBar.dragVelocityX < -500) {
                    console.log("⬅ SWIPE LEFT detected!");
                    swipeLeft();
                }
            }
            navBar.dragCurrentX = 0;
            navBar.dragCurrentY = 0;
            navBar.dragVelocityX = 0;
            navBar.dragVelocityY = 0;
            navBar.isDragging = false;
        }
        onCanceled: {
            navBar.dragCurrentX = 0;
            navBar.dragCurrentY = 0;
            navBar.dragVelocityX = 0;
            navBar.dragVelocityY = 0;
            navBar.isDragging = false;
        }
    }

    Text {
        visible: navBar.isDragging && navBar.dragCurrentX > navBar.swipeThreshold
        text: "◀ Previous"
        color: "#00CCCC"
        font.pixelSize: Constants.fontSizeSmall
        font.weight: Font.Bold
        anchors.left: parent.left
        anchors.leftMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        opacity: Math.min(1, navBar.dragCurrentX / 100)
    }

    Text {
        visible: navBar.isDragging && navBar.dragCurrentX < -navBar.swipeThreshold
        text: "Next ▶"
        color: "#00CCCC"
        font.pixelSize: Constants.fontSizeSmall
        font.weight: Font.Bold
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        opacity: Math.min(1, -navBar.dragCurrentX / 100)
    }

    Text {
        visible: navBar.isDragging && navBar.dragCurrentY < -navBar.swipeThreshold
        text: "▲ Apps"
        color: "#00CCCC"
        font.pixelSize: Constants.fontSizeSmall
        font.weight: Font.Bold
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: Math.min(40, -navBar.dragCurrentY)
        opacity: Math.min(1, -navBar.dragCurrentY / 80)
    }
}
