import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Hub row: unread dot, a glass-ring monogram or icon, then sender and
// time, account and a one-line snippet, laid out as Sailfish's events.
Item {
    id: row

    property bool unread: false
    property string avatarText: ""
    property string avatarIcon: ""
    property string name: ""
    property string time: ""
    property string account: ""
    property string snippet: ""
    readonly property bool down: area.pressed && area.containsMouse

    signal activated

    implicitHeight: Math.max(Silica.Theme.itemSizeLarge, textColumn.implicitHeight + Silica.Theme.paddingMedium * 2)

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
            anchors.centerIn: parent
            text: row.avatarText
            color: Silica.Theme.highlightColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeSmall
            visible: row.avatarText.length > 0
        }
        GlyphIcon {
            anchors.centerIn: parent
            name: row.avatarIcon
            size: Silica.Theme.iconSizeExtraSmall
            color: Silica.Theme.highlightColor
            visible: row.avatarText.length === 0 && row.avatarIcon.length > 0
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
    }

    MouseArea {
        id: area
        anchors.fill: parent
        onClicked: row.activated()
    }
}
