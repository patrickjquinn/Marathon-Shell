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
    readonly property bool canReply: {
        for (const a of (currentToast && currentToast.actions) || []) {
            if (a && (a.key === "inline-reply" || a.id === "inline-reply"))
                return true;
        }
        return false;
    }
    // Position follows state, so a late height change can't strand it.
    property bool shown: false
    property real dragOffset: 0
    // The open app, blurred behind the banner; the wallpaper otherwise.

    // In arrival order; a critical one goes ahead of all but earlier
    // critical ones.
    function showToast(notification) {
        // A newer text in the thread being answered takes over the banner,
        // keeping the reply.
        if (showInlineReply && currentToast && notification.replyTarget && notification.replyTarget === currentToast.replyTarget) {
            currentToast = notification;
            return;
        }
        const critical = n => n.urgency >= 2;
        const at = critical(notification) ? toastQueue.findIndex(n => !critical(n)) : -1;
        toastQueue.splice(at < 0 ? toastQueue.length : at, 0, notification);
        if (!currentToast)
            showNextToast();
    }

    // A notification closed before its banner showed loses the banner.
    // One being replied to stays: its replacement may take it over.
    function forget(id) {
        toastQueue = toastQueue.filter(n => n.id !== id);
        if (currentToast && currentToast.id === id && !showInlineReply)
            dismissToast();
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

    function openReply() {
        showInlineReply = true;
        autoHideTimer.stop();
        replyField.forceActiveFocus();
    }

    function invokeAction(key) {
        NotificationService.triggerAction(currentToast.id, key);
        dismissToast();
    }

    function sendReply() {
        if (!currentToast || replyField.text.trim().length === 0)
            return;
        NotificationService.reply(currentToast.id, replyField.text);
        dismissToast();
    }

    function dismissToast() {
        if (!currentToast)
            return;
        autoHideTimer.stop();
        showInlineReply = false;
        replyField.text = "";
        shown = false;
        dragOffset = 0;
        hideTimer.restart();
    }

    anchors.fill: parent
    z: 3000

    Connections {
        target: NotificationService
        function onNotificationDismissed(id) {
            toastContainer.forget(id);
        }
    }

    Item {
        id: toast

        anchors.left: parent.left
        anchors.right: parent.right
        y: (toastContainer.shown ? Constants.statusBarHeight : -height) + toastContainer.dragOffset
        // Derived from the row it has to hold, not a fixed 72/140. The
        // title and body are scaled type tokens while these heights were
        // physical px, so at 1.5x the two lines overflowed the card and
        // painted over the status bar and the surface underneath.
        height: body.implicitHeight + Silica.Theme.paddingLarge * 2
        visible: false

        // An edge-to-edge band of the ambience, lit along its lower edge
        // in the highlight, as Sailfish's banners were.
        Rectangle {
            anchors.fill: parent
            color: Silica.Theme.rgba(Silica.Theme.highlightDimmerColor, 0.95)
        }
        MGlowLine {
            objectName: "bannerGlow"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }

        Column {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Silica.Theme.paddingLarge
            anchors.leftMargin: Silica.Theme.horizontalPageMargin
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            spacing: Silica.Theme.paddingSmall

            Row {
                id: mainContent

                width: parent.width
                // Whichever is taller: the icon tile or the two text lines.
                height: Math.max(iconTile.height, textColumn.implicitHeight)
                spacing: Silica.Theme.paddingLarge

                Rectangle {
                    id: iconTile
                    width: Silica.Theme.iconSizeMedium
                    height: width
                    radius: width / 2
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.18)
                    anchors.verticalCenter: parent.verticalCenter

                    NotificationIcon {
                        objectName: "bannerIcon"
                        anchors.centerIn: parent
                        source: (toastContainer.currentToast && toastContainer.currentToast.icon) || ""
                        category: (toastContainer.currentToast && toastContainer.currentToast.category) || ""
                        size: Silica.Theme.iconSizeExtraSmall
                        color: Silica.Theme.highlightColor
                    }
                }

                Column {
                    id: textColumn
                    width: parent.width - iconTile.width - Silica.Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        text: (toastContainer.currentToast && toastContainer.currentToast.title) ? toastContainer.currentToast.title : ""
                        color: Silica.Theme.primaryColor
                        font.pixelSize: Silica.Theme.fontSizeSmall
                        font.weight: Font.DemiBold
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

            NotificationActions {
                objectName: "bannerActions"
                // Button text lines up under the title.
                x: iconTile.width + mainContent.spacing - Silica.Theme.paddingLarge
                availableWidth: parent.width - x
                actions: (toastContainer.currentToast && toastContainer.currentToast.actions) || []
                useIcons: !!(toastContainer.currentToast && toastContainer.currentToast.actionIcons)
                reply: toastContainer.canReply
                visible: buttons.length > 0 && !toastContainer.showInlineReply
                onInvoked: key => key === "inline-reply" ? toastContainer.openReply() : toastContainer.invokeAction(key)
            }

            Row {
                id: replyRow

                width: parent.width
                spacing: Silica.Theme.paddingSmall
                visible: toastContainer.showInlineReply

                Silica.TextField {
                    id: replyField

                    objectName: "replyField"
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
                NotificationService.markAsRead(n.id);
                toastContainer.dismissToast();
            }
        }

        Behavior on y {
            enabled: !bannerArea.pressed

            NumberAnimation {
                duration: MMotion.ms(MMotion.moderate)
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: MMotion.ms(MMotion.quick)
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
