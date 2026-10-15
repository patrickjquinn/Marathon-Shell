import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: toastContainer

    property var toastQueue: []
    property var currentToast: null
    property bool showInlineReply: false
    // Only a sender that advertised inline-reply can receive the text.
    readonly property bool canReply: !!currentToast && Array.isArray(currentToast.actions) && currentToast.actions.some(a => a && (a.key === "inline-reply" || a.id === "inline-reply"))
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

    function sendReply() {
        if (!currentToast || replyField.text.trim().length === 0)
            return;
        FreedesktopNotifications.InvokeReply(currentToast.id, replyField.text);
        dismissToast();
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
                ? mainContent.height + replyRow.height + Silica.Theme.paddingSmall + Silica.Theme.paddingMedium * 2
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

                width: parent.width - Silica.Theme.paddingMedium * 2 - (replyAction.visible ? replyAction.width : 0)
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

            Silica.BackgroundItem {
                id: replyAction

                anchors.right: parent.right
                anchors.verticalCenter: mainContent.verticalCenter
                width: replyLabel.implicitWidth + Silica.Theme.paddingLarge * 2
                height: Silica.Theme.itemSizeExtraSmall
                visible: toastContainer.canReply && !toastContainer.showInlineReply
                onClicked: {
                    toastContainer.showInlineReply = true;
                    autoHideTimer.stop();
                    replyField.forceActiveFocus();
                }

                Silica.Label {
                    id: replyLabel

                    anchors.centerIn: parent
                    text: qsTr("Reply")
                    color: replyAction.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                }
            }

            Row {
                id: replyRow

                width: parent.width - Silica.Theme.paddingMedium * 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: mainContent.bottom
                anchors.topMargin: Silica.Theme.paddingSmall
                spacing: Silica.Theme.paddingSmall
                visible: toastContainer.showInlineReply

                Silica.TextField {
                    id: replyField

                    width: parent.width - sendButton.width - parent.spacing
                    placeholderText: (toastContainer.currentToast && toastContainer.currentToast.replyPlaceholder) || qsTr("Reply")
                    labelVisible: false
                    textLeftMargin: 0
                    Keys.onReturnPressed: toastContainer.sendReply()
                    Keys.onEscapePressed: {
                        toastContainer.showInlineReply = false;
                        text = "";
                    }
                }

                Silica.Button {
                    id: sendButton

                    anchors.verticalCenter: replyField.verticalCenter
                    text: qsTr("Send")
                    preferredWidth: Silica.Theme.buttonWidthExtraSmall
                    enabled: replyField.text.trim().length > 0
                    onClicked: toastContainer.sendReply()
                }
            }
        }

        MouseArea {
            id: bannerArea

            property real startY: 0
            property bool dragged: false

            anchors.fill: parent
            z: -1
            onPressed: mouse => {
                startY = mapToItem(toastContainer, mouse.x, mouse.y).y;
                dragged = false;
                autoHideTimer.stop();
            }
            onPositionChanged: mouse => {
                const dy = mapToItem(toastContainer, mouse.x, mouse.y).y - startY;
                if (Math.abs(dy) > Silica.Theme.startDragDistance)
                    dragged = true;
                toastContainer.dragOffset = Math.max(Math.min(0, dy), -toast.height);
            }
            onReleased: {
                if (toastContainer.dragOffset < -Silica.Theme.startDragDistance * 2) {
                    toastContainer.dismissToast();
                } else {
                    toastContainer.dragOffset = 0;
                    if (!toastContainer.showInlineReply)
                        autoHideTimer.restart();
                }
            }
            onClicked: {
                if (dragged || !toastContainer.currentToast)
                    return;
                const n = toastContainer.currentToast;
                NotificationService.clickNotification(n.id);
                NotificationModel.markAsRead(n.id);
                if (n.appId)
                    NavigationRouter.navigateToDeepLink(n.appId, "", {
                        "notificationId": n.id,
                        "action": "view",
                        "from": "notification"
                    });
                else
                    Router.goToHub();
                toastContainer.dismissToast();
            }
        }

        Behavior on y {
            enabled: !bannerArea.pressed

            NumberAnimation {
                duration: MMotion.moderate
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.Bezier
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
