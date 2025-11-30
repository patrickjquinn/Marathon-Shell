import QtQuick
import MarathonOS.Shell

Rectangle {
    id: navBar
    height: Constants.navBarHeight
    color: "#000000"

    signal swipeLeft
    signal swipeRight
    signal swipeUp
    signal swipeUpRelease(real velocity)

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

    Rectangle {
        id: indicator
        anchors.centerIn: parent
        width: Constants.cardBannerHeight
        height: Constants.spacingXSmall
        radius: Constants.borderRadiusSmall
        color: "#FFFFFF"
        opacity: 0.8

        x: parent.width / 2 - width / 2 + (isDragging ? Math.max(-maxDragDistance, Math.min(maxDragDistance, dragCurrentX)) : 0)
        y: (isDragging && dragCurrentY < 0) ? Math.max(-60, dragCurrentY) : 0
        scale: isDragging ? 1.2 : 1.0

        Behavior on x {
            enabled: !isDragging
            SpringAnimation {
                spring: 3
                damping: 0.3
                duration: snapDuration
            }
        }

        Behavior on y {
            enabled: !isDragging
            SpringAnimation {
                spring: 3
                damping: 0.3
                duration: snapDuration
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
        opacity: isDragging ? 0.2 : 0

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
            dragStartX = mouse.x;
            dragStartY = mouse.y;
            lastDragX = mouse.x;
            lastDragY = mouse.y;
            dragCurrentX = 0;
            dragCurrentY = 0;
            dragVelocityX = 0;
            dragVelocityY = 0;
            lastDragTime = Date.now();
            isDragging = true;
            console.log(" Nav drag started at:", mouse.x, mouse.y);
        }

        onPositionChanged: mouse => {
            if (!isDragging)
                return;
            var now = Date.now();
            var deltaTime = now - lastDragTime;

            if (deltaTime > 0) {
                dragVelocityX = ((mouse.x - lastDragX) / deltaTime) * 1000;
                dragVelocityY = ((mouse.y - lastDragY) / deltaTime) * 1000;
            }

            dragCurrentX = mouse.x - dragStartX;
            dragCurrentY = mouse.y - dragStartY;

            lastDragX = mouse.x;
            lastDragY = mouse.y;
            lastDragTime = now;

            console.log(" Dragging:", dragCurrentX.toFixed(0), dragCurrentY.toFixed(0), "velocity:", dragVelocityX.toFixed(0), dragVelocityY.toFixed(0));
        }

        onReleased: mouse => {
            if (!isDragging)
                return;
            console.log(" Released. Distance:", dragCurrentX.toFixed(0), dragCurrentY.toFixed(0), "Velocity:", dragVelocityX.toFixed(0), dragVelocityY.toFixed(0));

            var absX = Math.abs(dragCurrentX);
            var absY = Math.abs(dragCurrentY);
            var absVelX = Math.abs(dragVelocityX);
            var absVelY = Math.abs(dragVelocityY);

            if (absY > absX) {
                if (dragCurrentY < -swipeThreshold || dragVelocityY < -500) {
                    console.log("⬆ SWIPE UP detected!");
                    swipeUp();
                    swipeUpRelease(Math.abs(dragVelocityY));
                }
            } else {
                if (dragCurrentX > swipeThreshold || dragVelocityX > 500) {
                    console.log("➡ SWIPE RIGHT detected!");
                    swipeRight();
                } else if (dragCurrentX < -swipeThreshold || dragVelocityX < -500) {
                    console.log("⬅ SWIPE LEFT detected!");
                    swipeLeft();
                }
            }

            dragCurrentX = 0;
            dragCurrentY = 0;
            dragVelocityX = 0;
            dragVelocityY = 0;
            isDragging = false;
        }

        onCanceled: {
            dragCurrentX = 0;
            dragCurrentY = 0;
            dragVelocityX = 0;
            dragVelocityY = 0;
            isDragging = false;
        }
    }

    Text {
        visible: isDragging && dragCurrentX > swipeThreshold
        text: "◀ Previous"
        color: "#00CCCC"
        font.pixelSize: Constants.fontSizeSmall
        font.weight: Font.Bold
        anchors.left: parent.left
        anchors.leftMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        opacity: Math.min(1.0, dragCurrentX / 100)
    }

    Text {
        visible: isDragging && dragCurrentX < -swipeThreshold
        text: "Next ▶"
        color: "#00CCCC"
        font.pixelSize: Constants.fontSizeSmall
        font.weight: Font.Bold
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingLarge
        anchors.verticalCenter: parent.verticalCenter
        opacity: Math.min(1.0, -dragCurrentX / 100)
    }

    Text {
        visible: isDragging && dragCurrentY < -swipeThreshold
        text: "▲ Apps"
        color: "#00CCCC"
        font.pixelSize: Constants.fontSizeSmall
        font.weight: Font.Bold
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: Math.min(40, -dragCurrentY)
        opacity: Math.min(1.0, -dragCurrentY / 80)
    }
}
