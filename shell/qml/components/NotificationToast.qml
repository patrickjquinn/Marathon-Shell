import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: toastContainer

    property var toastQueue: []
    property var currentToast: null
    onCurrentToastChanged: appCapture.scheduleUpdate()
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
    property Item backdropSource: null

    // In arrival order; a critical one goes ahead of all but earlier
    // critical ones.
    function showToast(notification) {
        const critical = n => n.urgency >= 2;
        const at = critical(notification) ? toastQueue.findIndex(n => !critical(n)) : -1;
        toastQueue.splice(at < 0 ? toastQueue.length : at, 0, notification);
        if (!currentToast)
            showNextToast();
    }

    // A notification closed before its banner showed loses the banner.
    function forget(id) {
        toastQueue = toastQueue.filter(n => n.id !== id);
        if (currentToast && currentToast.id === id)
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
        FreedesktopNotifications.InvokeReply(currentToast.id, replyField.text);
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

    MGlassBackdrop {
        id: wallpaperGlass

        anchors.fill: parent
        visible: toast.visible && !toastContainer.backdropSource
    }

    ShaderEffectSource {
        id: appCapture

        width: toast.width
        height: toast.height
        sourceItem: toast.visible ? toastContainer.backdropSource : null
        // Where the toast lands, captured once per toast, not each frame it
        // slides or the app under it draws.
        sourceRect: Qt.rect(toast.x, Constants.statusBarHeight, toast.width, toast.height)
        textureSize: Qt.size(Math.max(1, Math.round(toast.width / 2)), Math.max(1, Math.round(toast.height / 2)))
        live: false
        onSourceItemChanged: scheduleUpdate()
        onSourceRectChanged: scheduleUpdate()
        visible: false
    }

    MultiEffect {
        id: appBlur

        width: toast.width
        height: toast.height
        source: appCapture
        autoPaddingEnabled: false
        blurEnabled: !MMotion.reduceBlur
        blur: 1.0
        blurMax: 32
        saturation: 0.3
        brightness: -0.02
        visible: false
    }

    ShaderEffectSource {
        id: appGlass

        width: toast.width
        height: toast.height
        sourceItem: toastContainer.backdropSource && toast.visible ? appBlur : null
        hideSource: true
        visible: false
    }

    Item {
        id: toast

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Silica.Theme.paddingSmall
        y: (toastContainer.shown ? Constants.statusBarHeight : -height) + toastContainer.dragOffset
        // Derived from the row it has to hold, not a fixed 72/140. The
        // title and body are scaled type tokens while these heights were
        // physical px, so at 1.5x the two lines overflowed the card and
        // painted over the status bar and the surface underneath.
        height: body.implicitHeight + Silica.Theme.paddingLarge * 2
        visible: false

        MGlassPlatter {
            anchors.fill: parent
            backdrop: toastContainer.backdropSource ? appGlass : wallpaperGlass.texture
            screenSpaceLookup: !toastContainer.backdropSource
        }

        Column {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Silica.Theme.paddingLarge
            spacing: Silica.Theme.paddingSmall

            Row {
                id: mainContent

                width: parent.width
                // Whichever is taller: the icon tile or the two text lines.
                height: Math.max(iconTile.height, textColumn.implicitHeight)
                spacing: Silica.Theme.paddingLarge

                NotificationIcon {
                    id: iconTile
                    objectName: "bannerIcon"
                    source: (toastContainer.currentToast && toastContainer.currentToast.icon) || ""
                    category: (toastContainer.currentToast && toastContainer.currentToast.category) || ""
                    size: Silica.Theme.iconSizeSmallPlus
                    color: Silica.Theme.highlightColor
                    anchors.verticalCenter: parent.verticalCenter
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
                if (!n.appId)
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
