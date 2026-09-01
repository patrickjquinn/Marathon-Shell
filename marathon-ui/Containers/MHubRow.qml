import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Hub row (unified inbox).
//
// Min-height 72 design-px row: optional 8 × 8 unread dot at the left edge,
// 40 × 40 monogram-or-icon avatar with a per-contact tint, then the
// content column — name + time row, account label, single-line
// snippet. The snippet clamps to one line with ellipsis.
//
// Used by MarathonHub. Same pattern is reusable for other glass
// inboxes (search results, notification stack).
Item {
    id: row

    // Content — caller wires.
    property bool unread: false
    property color avatarTint: MColors.bb10Elevated
    property string avatarText: ""           // monogram letters
    property string avatarIcon: ""           // icon glyph (used when avatarText is empty)
    property bool avatarUsesTealBorder: false
    property color avatarTextColor: "#ffffff"
    property string name: ""
    property string time: ""
    property string account: ""              // "iMessage", "Mail", "Work", etc.
    property string snippet: ""

    signal activated

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    // 72 design-px is the DS minimum, not a fixed height. The row stacks
    // three scaled type tokens (subhead + caption + footnote); at 1.5x
    // their line-boxes alone exceed 72 physical px, so a fixed 72 clipped
    // the snippet. Scale the minimum and let real content raise it.
    readonly property real vPadding: Math.round(10 * scaleFactor)
    implicitHeight: Math.max(Math.round(72 * scaleFactor),
                             textColumn.implicitHeight + vPadding * 2)

    Rectangle {
        anchors.fill: parent
        color: hover.containsMouse ? MColors.whiteOverlay02 : "transparent"
    }

    // ── Unread dot ─────────────────────────────────────────
    Rectangle {
        id: dot
        width: Math.round(8 * row.scaleFactor)
        height: width
        radius: width / 2
        anchors.left: parent.left
        anchors.leftMargin: Math.round(8 * row.scaleFactor)
        anchors.verticalCenter: parent.verticalCenter
        color: MColors.marathonTealBright
        visible: row.unread

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(16 * row.scaleFactor)
            height: width
            radius: width / 2
            color: MColors.marathonTealGlow
            opacity: 0.18
            z: -1
        }
    }

    // ── Avatar ─────────────────────────────────────────────
    Rectangle {
        id: avatar
        width: Math.round(40 * row.scaleFactor)
        height: width
        radius: width / 2
        anchors.left: parent.left
        anchors.leftMargin: Math.round(24 * row.scaleFactor)
        anchors.verticalCenter: parent.verticalCenter
        color: row.avatarTint
        border.width: 1
        border.color: row.avatarUsesTealBorder ? MColors.tealBorder : MColors.whiteOverlay08

        Text {
            anchors.centerIn: parent
            text: row.avatarText
            color: row.avatarTextColor
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeSubhead
            font.weight: MTypography.weightMedium
            visible: row.avatarText.length > 0
        }
        Icon {
            anchors.centerIn: parent
            name: row.avatarIcon
            size: Math.round(18 * row.scaleFactor)
            color: row.avatarTextColor
            visible: row.avatarText.length === 0 && row.avatarIcon.length > 0
        }
    }

    // ── Text content ───────────────────────────────────────
    Column {
        id: textColumn
        anchors.left: avatar.right
        anchors.leftMargin: Math.round(14 * row.scaleFactor)
        anchors.right: parent.right
        anchors.rightMargin: Math.round(20 * row.scaleFactor)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(2 * row.scaleFactor)

        // Name + time
        Item {
            width: parent.width
            height: nameText.implicitHeight

            Text {
                id: nameText
                anchors.left: parent.left
                anchors.right: timeText.left
                anchors.rightMargin: Math.round(10 * row.scaleFactor)
                anchors.verticalCenter: parent.verticalCenter
                text: row.name
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeSubhead
                font.weight: row.unread ? MTypography.weightDemiBold : MTypography.weightMedium
                elide: Text.ElideRight
            }
            Text {
                id: timeText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: row.time
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeCaption
                font.features: ({
                        "tnum": 1
                    })
            }
        }

        // Account
        Text {
            width: parent.width
            text: row.account
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeCaption
            font.weight: MTypography.weightRegular
            elide: Text.ElideRight
            visible: text.length > 0
        }

        // Snippet — single-line clamp.
        Text {
            width: parent.width
            text: row.snippet
            color: row.unread ? MColors.textPrimary : MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
            font.weight: MTypography.weightRegular
            elide: Text.ElideRight
            visible: text.length > 0
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: row.activated()
    }
}
