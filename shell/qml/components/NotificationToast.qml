import MarathonOS.Shell 1.0
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

Item {
    id: toastContainer

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property var toastQueue: []
    property var currentToast: null
    property bool showInlineReply: false

    function showToast(notification) {
        toastQueue.push(notification);
        if (!currentToast)
            showNextToast();
    }

    function showNextToast() {
        if (toastQueue.length === 0) {
            currentToast = null;
            return;
        }
        currentToast = toastQueue.shift();
        toast.visible = true;
        toast.y = -toast.height;
        slideIn.start();
        autoHideTimer.restart();
    }

    function dismissToast() {
        autoHideTimer.stop();
        showInlineReply = false;
        replyField.text = "";
        slideOut.start();
    }

    anchors.fill: parent
    z: 3000

    MCard {
        id: toast

        anchors.left: parent.left
        anchors.right: parent.right
        y: -height
        width: parent.width
        // Derived from the row it has to hold, not a fixed 72/140. The
        // title and body are scaled type tokens while these heights were
        // physical px, so at 1.5x the two lines overflowed the card and
        // painted over the status bar and the surface underneath.
        height: toastContainer.showInlineReply
                ? mainContent.height + replyRow.height + MSpacing.sm + MSpacing.xs * 2
                : mainContent.height + MSpacing.md
        elevation: 0
        radius: 0
        visible: false
        layer.enabled: true

        Item {
            anchors.fill: parent

            Row {
                id: mainContent

                width: parent.width - MSpacing.md * 2
                // Whichever is taller: the icon tile or the two text lines.
                height: Math.max(iconTile.height, textColumn.implicitHeight)
                anchors.left: parent.left
                anchors.leftMargin: MSpacing.md
                anchors.verticalCenter: toastContainer.showInlineReply ? undefined : parent.verticalCenter
                anchors.top: toastContainer.showInlineReply ? parent.top : undefined
                anchors.topMargin: toastContainer.showInlineReply ? MSpacing.xs : 0
                spacing: MSpacing.md

                Rectangle {
                    id: iconTile
                    width: Math.round(48 * toastContainer.scaleFactor)
                    height: width
                    radius: MRadius.md
                    color: MColors.elevated
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        name: (toastContainer.currentToast && toastContainer.currentToast.icon) ? toastContainer.currentToast.icon : "bell"
                        size: Math.round(24 * toastContainer.scaleFactor)
                        color: MColors.textPrimary
                        anchors.centerIn: parent
                    }
                }

                Column {
                    id: textColumn
                    width: parent.width - iconTile.width - MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(2 * toastContainer.scaleFactor)

                    MLabel {
                        text: (toastContainer.currentToast && toastContainer.currentToast.title) ? toastContainer.currentToast.title : ""
                        variant: "primary"
                        font.weight: MTypography.weightBold
                        font.pixelSize: MTypography.sizeBody
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    MLabel {
                        text: (toastContainer.currentToast && toastContainer.currentToast.body) ? toastContainer.currentToast.body : ""
                        variant: "secondary"
                        font.pixelSize: MTypography.sizeSmall
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        width: parent.width
                    }
                }
            }

            Row {
                id: replyRow
                width: parent.width - MSpacing.xs * 2
                height: Math.round(48 * toastContainer.scaleFactor)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: mainContent.bottom
                anchors.topMargin: MSpacing.sm
                spacing: MSpacing.sm
                visible: toastContainer.showInlineReply

                MTextInput {
                    id: replyField

                    width: parent.width - sendButton.width - MSpacing.sm
                    height: Math.round(40 * toastContainer.scaleFactor)
                    placeholderText: "Reply..."
                    onAccepted: {
                        if (text.trim().length > 0 && toastContainer.currentToast) {
                            Logger.info("NotificationToast", "Sending inline reply: " + text);
                            FreedesktopNotifications.InvokeReply(toastContainer.currentToast.id, text);
                            text = "";
                            toastContainer.showInlineReply = false;
                            dismissToast();
                        }
                    }
                    Keys.onEscapePressed: {
                        toastContainer.showInlineReply = false;
                        text = "";
                    }
                }

                MButton {
                    id: sendButton

                    text: "Send"
                    width: Math.round(80 * toastContainer.scaleFactor)
                    height: Math.round(40 * toastContainer.scaleFactor)
                    enabled: replyField.text.trim().length > 0
                    onClicked: replyField.accepted()
                }
            }
        }

        MouseArea {
            property real startY: 0
            property real dragY: 0

            anchors.fill: parent
            z: -1
            onPressed: mouse => {
                startY = mouse.y;
                dragY = 0;
                autoHideTimer.stop();
            }
            onPositionChanged: mouse => {
                dragY = mouse.y - startY;
                if (dragY < 0)
                    toast.y = Math.max(toast.y + dragY * 0.5, -toast.height);
            }
            onReleased: mouse => {
                if (dragY < -30) {
                    dismissToast();
                } else {
                    toast.y = Constants.statusBarHeight;
                    autoHideTimer.restart();
                }
            }
            onClicked: {
                var supportsInlineReply = toastContainer.currentToast && (toastContainer.currentToast.appId === "messages" || toastContainer.currentToast.appId === "org.telegram.desktop" || toastContainer.currentToast.appId === "signal-desktop" || (toastContainer.currentToast.category && toastContainer.currentToast.category.includes("message")));
                if (supportsInlineReply && !toastContainer.showInlineReply) {
                    Logger.info("NotificationToast", "Showing inline reply for: " + toastContainer.currentToast.id);
                    toastContainer.showInlineReply = true;
                    autoHideTimer.stop();
                    Qt.callLater(function () {
                        replyField.forceActiveFocus();
                    });
                } else if (!toastContainer.showInlineReply) {
                    Logger.info("NotificationToast", "Toast tapped: " + toastContainer.currentToast.id);
                    NotificationService.clickNotification(toastContainer.currentToast.id);
                    NotificationModel.markAsRead(toastContainer.currentToast.id);
                    if (toastContainer.currentToast.appId)
                        NavigationRouter.navigateToDeepLink(toastContainer.currentToast.appId, "", {
                            "notificationId": toastContainer.currentToast.id,
                            "action": "view",
                            "from": "notification"
                        });
                    else
                        Router.goToHub();
                    dismissToast();
                }
            }
        }

        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#40000000"
            shadowOpacity: 0.3
            shadowBlur: 0.6
            shadowVerticalOffset: 4
            shadowHorizontalOffset: 0
        }

        Behavior on y {
            NumberAnimation {
                duration: MMotion.moderate
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: MMotion.quick
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }
    }

    NumberAnimation {
        id: slideIn

        target: toast
        property: "y"
        to: Constants.statusBarHeight
        duration: 400
        easing.type: Easing.OutBack
        easing.overshoot: 1.2
    }

    NumberAnimation {
        id: slideOut

        target: toast
        property: "y"
        to: -toast.height
        duration: MMotion.quick
        easing.bezierCurve: MMotion.easingAccelerateCurve
        onFinished: {
            toast.visible = false;
            toastContainer.showNextToast();
        }
    }

    Timer {
        id: autoHideTimer

        interval: 5000
        onTriggered: dismissToast()
    }
}
