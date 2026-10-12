import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: toastContainer

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property var toastQueue: []
    property var currentToast: null
    property bool showInlineReply: false
    // Position follows state, so a late height change can't strand it.
    property bool shown: false
    property real dragOffset: 0

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
        dragOffset = 0;
        shown = true;
        autoHideTimer.restart();
    }

    function dismissToast() {
        autoHideTimer.stop();
        showInlineReply = false;
        replyField.text = "";
        shown = false;
        dragOffset = 0;
        hideTimer.restart();
    }

    anchors.fill: parent
    z: 3000

    Rectangle {
        id: toast

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Silica.Theme.paddingSmall
        y: (toastContainer.shown ? Constants.statusBarHeight : -height) + toastContainer.dragOffset
        // Derived from the row it has to hold, not a fixed 72/140. The
        // title and body are scaled type tokens while these heights were
        // physical px, so at 1.5x the two lines overflowed the card and
        // painted over the status bar and the surface underneath.
        height: toastContainer.showInlineReply
                ? mainContent.height + replyRow.height + MSpacing.sm + MSpacing.xs * 2
                : mainContent.height + Silica.Theme.paddingLarge
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        visible: false

        Item {
            anchors.fill: parent

            Row {
                id: mainContent

                width: parent.width - Silica.Theme.paddingMedium * 2
                // Whichever is taller: the icon tile or the two text lines.
                height: Math.max(iconTile.height, textColumn.implicitHeight)
                anchors.left: parent.left
                anchors.leftMargin: Silica.Theme.paddingMedium
                anchors.verticalCenter: toastContainer.showInlineReply ? undefined : parent.verticalCenter
                anchors.top: toastContainer.showInlineReply ? parent.top : undefined
                anchors.topMargin: toastContainer.showInlineReply ? Silica.Theme.paddingMedium : 0
                spacing: Silica.Theme.paddingMedium

                GlyphIcon {
                    id: iconTile
                    name: (toastContainer.currentToast && toastContainer.currentToast.icon) ? toastContainer.currentToast.icon : "bell"
                    size: Silica.Theme.iconSizeSmallPlus
                    color: Silica.Theme.highlightColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    id: textColumn
                    width: parent.width - iconTile.width - Silica.Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        text: (toastContainer.currentToast && toastContainer.currentToast.title) ? toastContainer.currentToast.title : ""
                        color: Silica.Theme.primaryColor
                        font.pixelSize: Silica.Theme.fontSizeSmall
                        truncationMode: Silica.TruncationMode.Fade
                        width: parent.width
                    }

                    Silica.Label {
                        visible: text.length > 0
                        text: (toastContainer.currentToast && toastContainer.currentToast.body) ? toastContainer.currentToast.body : ""
                        color: Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
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
                            toastContainer.dismissToast();
                        }
                    }
                    Keys.onEscapePressed: {
                        toastContainer.showInlineReply = false;
                        text = "";
                    }
                }

                Silica.Button {
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
                toastContainer.dragOffset = Math.max(Math.min(0, dragY * 0.5), -toast.height);
            }
            onReleased: mouse => {
                if (dragY < -30) {
                    toastContainer.dismissToast();
                } else {
                    toastContainer.dragOffset = 0;
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
                    toastContainer.dismissToast();
                }
            }
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

    Timer {
        id: hideTimer

        interval: MMotion.moderate
        onTriggered: {
            toast.visible = false;
            toastContainer.showNextToast();
        }
    }

    Timer {
        id: autoHideTimer

        interval: 5000
        onTriggered: toastContainer.dismissToast()
    }
}
