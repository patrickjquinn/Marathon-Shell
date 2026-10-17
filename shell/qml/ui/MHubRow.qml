import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Hub row: unread dot, a glass-ring monogram or icon, then sender and
// time, account and a one-line snippet, laid out as Sailfish's events.
// Swiping it to the right dismisses it; leftward stays with the pager.
Item {
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
    property string name: ""
    property string time: ""
    property string account: ""
    property string snippet: ""
    readonly property bool down: area.pressed && area.containsMouse && !area.swiping
    property real collapse: 1
    readonly property real fullHeight: Math.max(Silica.Theme.itemSizeLarge, textColumn.implicitHeight + Silica.Theme.paddingMedium * 2)

    signal activated
    signal actionInvoked(string key)
    signal dismissed

    function reset() {
        dismissAnimation.stop();
        snapBack.stop();
        content.x = 0;
        collapse = 1;
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

        Rectangle {
            width: Silica.Theme.paddingSmall
            height: width
            radius: width / 2
            anchors.left: parent.left
            anchors.leftMargin: Silica.Theme.paddingSmall
            anchors.verticalCenter: parent.verticalCenter
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
            color: "transparent"
            border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
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
                size: drawsGlyph ? Silica.Theme.iconSizeExtraSmall : Silica.Theme.iconSizeSmall
                color: Silica.Theme.highlightColor
                visible: hasImage || drawsGlyph
                anchors.centerIn: parent
            }
        }

        Column {
            id: textColumn
            anchors.left: avatar.right
            anchors.leftMargin: Silica.Theme.paddingMedium
            anchors.right: parent.right
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter

            Item {
                width: parent.width
                height: nameText.implicitHeight

                Silica.Label {
                    id: nameText
                    anchors.left: parent.left
                    anchors.right: timeText.left
                    anchors.rightMargin: Silica.Theme.paddingSmall
                    text: row.name
                    color: row.down ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
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
                truncationMode: Silica.TruncationMode.Fade
                visible: text.length > 0
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
                onInvoked: key => row.actionInvoked(key)
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
            if (!swiping && dx > Qt.styleHints.startDragDistance / 2 && dx > 2 * Math.abs(mouse.y - pressY)) {
                swiping = true;
                preventStealing = true;
            }
            if (swiping)
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
