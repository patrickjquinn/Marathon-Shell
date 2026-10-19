import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Hub row: unread dot, a glass-ring monogram or icon, then sender and
// time, account and a one-line snippet, laid out as Sailfish's events.
// Swiping it to the right dismisses it; leftward stays with the pager.
// An ongoing row shows its progress and can't be swiped away.
// A focus scope: the list focuses its current row, which must leave the
// reply field its focus.
FocusScope {
    id: row

    property bool unread: false
    property string avatarText: ""
    property string avatarIcon: ""
    // The notification's own picture or glyph, shown in place of the monogram.
    property string image: ""
    // A message's glyph names only the app; its sender's monogram says more.
    property bool glyphReplacesMonogram: true
    property var actions: []
    property bool actionIcons: false
    // Only a sender that advertised inline-reply can receive the text. The
    // model's actions are a sequence, not a JS array.
    readonly property bool canReply: {
        for (const a of actions || []) {
            if (a && (a.key === "inline-reply" || a.id === "inline-reply"))
                return true;
        }
        return false;
    }
    property bool replying: false
    property string name: ""
    property string time: ""
    property string account: ""
    property string snippet: ""
    property bool ongoing: false
    // 0..1, or negative while unknown.
    property real progress: -1
    readonly property bool down: area.pressed && area.containsMouse && !area.swiping && !tapTimeout.running

    Timer {
        id: tapTimeout

        interval: MMotion.tapTimeout
        running: area.pressed
    }
    property real collapse: 1
    readonly property real fullHeight: Math.max(Silica.Theme.itemSizeLarge, textColumn.implicitHeight + Silica.Theme.paddingLarge * 2)

    signal activated
    signal actionInvoked(string key)
    signal replied(string text)
    signal dismissed

    function reset() {
        dismissAnimation.stop();
        snapBack.stop();
        content.x = 0;
        collapse = 1;
        replying = false;
        replyField.text = "";
    }

    function sendReply() {
        const text = replyField.text.trim();
        if (text.length === 0)
            return;
        replying = false;
        replyField.text = "";
        replied(text);
    }

    implicitHeight: fullHeight * collapse
    clip: collapse < 1
    ListView.onReused: reset()

    SequentialAnimation {
        id: dismissAnimation

        NumberAnimation {
            target: content
            property: "x"
            to: row.width
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: row
            property: "collapse"
            to: 0
            duration: MMotion.quick
            easing.type: Easing.InOutQuad
        }
        ScriptAction {
            script: row.dismissed()
        }
    }

    NumberAnimation {
        id: snapBack

        target: content
        property: "x"
        to: 0
        duration: MMotion.quick
        easing.type: Easing.OutCubic
    }

    Item {
        id: content

        width: row.width
        height: row.fullHeight
        opacity: 1 - x / Math.max(1, row.width)

        Rectangle {
            anchors.fill: parent
            color: row.down ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"
        }

        // Sailfish's lit glass mark for what is new.
        Silica.GlassItem {
            objectName: "hubRowUnread"
            width: Silica.Theme.itemSizeExtraSmall * 0.6
            height: width
            x: (Silica.Theme.horizontalPageMargin - width) / 2
            anchors.verticalCenter: avatar.verticalCenter
            color: Silica.Theme.highlightColor
            visible: row.unread
        }

        Rectangle {
            id: avatar
            width: Silica.Theme.iconSizeMedium
            height: width
            radius: width / 2
            anchors.left: parent.left
            anchors.leftMargin: Silica.Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            // Read rows step back, as BB10's monochrome icons did.
            opacity: row.unread || row.ongoing ? 1 : 0.55
            color: "transparent"
            // An app icon or a picture stands on its own; the ring frames a
            // monogram or a glyph.
            border.width: picture.hasImage ? 0 : Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
            border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

            Text {
                objectName: "hubRowMonogram"
                anchors.centerIn: parent
                text: row.avatarText
                color: Silica.Theme.highlightColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeSmall
                visible: row.avatarText.length > 0 && !picture.visible
            }
            GlyphIcon {
                anchors.centerIn: parent
                name: row.avatarIcon
                size: Silica.Theme.iconSizeExtraSmall
                color: Silica.Theme.highlightColor
                visible: row.avatarText.length === 0 && row.avatarIcon.length > 0 && !picture.visible
            }
            NotificationIcon {
                id: picture
                readonly property bool drawsGlyph: isGlyph && row.glyphReplacesMonogram
                objectName: "hubRowImage"
                source: row.image
                size: drawsGlyph ? Silica.Theme.iconSizeExtraSmall : avatar.width
                color: Silica.Theme.highlightColor
                visible: hasImage || drawsGlyph
                anchors.centerIn: parent
            }
        }

        Column {
            id: textColumn
            anchors.left: avatar.right
            anchors.leftMargin: Silica.Theme.paddingLarge
            anchors.right: parent.right
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Silica.Theme.paddingSmall / 2)

            Item {
                width: parent.width
                height: nameText.implicitHeight

                Silica.Label {
                    id: nameText
                    anchors.left: parent.left
                    anchors.right: timeText.left
                    anchors.rightMargin: Silica.Theme.paddingMedium
                    text: row.name
                    color: row.down ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                    font.weight: row.unread ? Font.DemiBold : Font.Normal
                    truncationMode: Silica.TruncationMode.Fade
                }
                Silica.Label {
                    id: timeText
                    anchors.right: parent.right
                    anchors.verticalCenter: nameText.verticalCenter
                    text: row.time
                    color: row.down ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    font.features: ({
                            "tnum": 1
                        })
                }
            }

            Silica.Label {
                width: parent.width
                text: row.snippet
                color: row.down ? Silica.Theme.highlightColor : (row.unread ? Silica.Theme.primaryColor : Silica.Theme.secondaryColor)
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                visible: text.length > 0
            }

            Item {
                objectName: "hubRowProgress"
                width: parent.width
                height: track.height + Silica.Theme.paddingSmall * 2
                visible: row.ongoing

                Rectangle {
                    id: track

                    width: parent.width
                    height: Math.max(2, Math.round(Silica.Theme.paddingSmall / 3))
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: avatar.border.color
                    clip: true

                    Rectangle {
                        id: fill

                        readonly property bool known: row.progress >= 0

                        objectName: "hubRowProgressFill"
                        width: known ? track.width * row.progress : track.width / 4
                        height: parent.height
                        radius: parent.radius
                        color: Silica.Theme.highlightColor

                        Behavior on width {
                            enabled: fill.known
                            NumberAnimation {
                                duration: MMotion.moderate
                                easing.type: Easing.OutCubic
                            }
                        }

                        NumberAnimation on x {
                            running: MMotion.gate(!fill.known && row.ongoing && row.visible)
                            from: -fill.width
                            to: track.width
                            duration: 1200
                            loops: Animation.Infinite
                            onRunningChanged: if (!running)
                                fill.x = 0
                        }
                    }
                }
            }

            Silica.Label {
                width: parent.width
                text: row.account
                color: row.down ? Silica.Theme.secondaryHighlightColor : Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeTiny
                truncationMode: Silica.TruncationMode.Fade
                visible: text.length > 0
            }

            NotificationActions {
                objectName: "hubRowActions"
                x: -Silica.Theme.paddingLarge
                availableWidth: parent.width + Silica.Theme.paddingLarge
                actions: row.actions
                useIcons: row.actionIcons
                reply: row.canReply
                visible: buttons.length > 0 && !row.replying
                onInvoked: key => {
                    if (key !== "inline-reply") {
                        row.actionInvoked(key);
                        return;
                    }
                    row.replying = true;
                    replyField.forceActiveFocus();
                }
            }

            Row {
                width: parent.width
                spacing: Silica.Theme.paddingSmall
                visible: row.replying

                Silica.TextField {
                    id: replyField

                    objectName: "hubRowReplyField"
                    width: parent.width - sendButton.width - parent.spacing
                    placeholderText: qsTr("Reply")
                    labelVisible: false
                    textLeftMargin: 0
                    Keys.onReturnPressed: row.sendReply()
                    Keys.onEscapePressed: {
                        row.replying = false;
                        text = "";
                    }
                }

                Silica.Button {
                    id: sendButton

                    objectName: "hubRowReplySend"
                    anchors.verticalCenter: replyField.verticalCenter
                    text: qsTr("Send")
                    preferredWidth: Silica.Theme.buttonWidthExtraSmall
                    enabled: replyField.text.trim().length > 0
                    onClicked: row.sendReply()
                }
            }
        }
    }

    // Beneath the content, so the action buttons take their own taps.
    MouseArea {
        id: area

        z: -1
        property real pressX: 0
        property real pressY: 0
        property bool swiping: false
        property bool swiped: false

        anchors.fill: parent
        enabled: !dismissAnimation.running
        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            swiping = false;
            swiped = false;
        }
        onPositionChanged: mouse => {
            const dx = mouse.x - pressX;
            // Claim the drag before the pager's own threshold so it can't steal it.
            if (!swiping && dx > Application.styleHints.startDragDistance / 2 && dx > 2 * Math.abs(mouse.y - pressY)) {
                swiping = true;
                preventStealing = true;
            }
            if (swiping && !row.ongoing)
                content.x = Math.max(0, dx);
        }
        onReleased: {
            if (!swiping)
                return;
            swiped = true;
            swiping = false;
            preventStealing = false;
            if (content.x > row.width / 3)
                dismissAnimation.start();
            else
                snapBack.start();
        }
        onCanceled: {
            swiping = false;
            preventStealing = false;
            snapBack.start();
        }
        onClicked: {
            if (!swiped)
                row.activated();
        }
    }
}
