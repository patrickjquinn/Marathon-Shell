import MarathonApp.Store
import MarathonOS.Shell
import MarathonUI.Theme
import QtQuick

// One app in a list: icon, name, one line of summary, rating, Get button.
// Tapping anywhere but the button opens the detail page.
Item {
    id: row

    required property var store
    required property var app
    property int rank: 0
    property bool showDivider: true

    readonly property string appId: app.app_id || app.id || ""
    readonly property var rating: store.ratingFor(appId)

    implicitHeight: store.dp(76)
    Component.onCompleted: {
        store.ensureRating(appId);
        store.ensureIcon(app);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            HapticService.light();
            row.store.openDetail(row.app);
        }
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: row.store.dp(12)

        Text {
            id: rankText
            anchors.verticalCenter: parent.verticalCenter
            visible: row.rank > 0
            width: visible ? row.store.dp(20) : 0
            text: row.rank
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeHeadline
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
        }

        AppIcon {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            width: row.store.dp(54)
            height: width
            source: row.store.iconFor(row.app)
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - (rankText.visible ? rankText.width + parent.spacing : 0) - icon.width - action.width - parent.spacing * 2
            spacing: row.store.dp(2)

            Text {
                width: parent.width
                text: row.app.name || row.appId
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeSubhead
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: row.app.summary || row.app.developer_name || (row.app.version ? "Version " + row.app.version : "")
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                elide: Text.ElideRight
            }
            Row {
                spacing: row.store.dp(5)
                visible: row.rating !== null
                StarRating {
                    anchors.verticalCenter: parent.verticalCenter
                    value: row.rating ? row.rating.average : 0
                    starSize: row.store.dp(10)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.rating ? row.store.formatCount(row.rating.total) : ""
                    color: MColors.textTertiary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeCaption
                }
            }
        }

        GetButton {
            id: action
            anchors.verticalCenter: parent.verticalCenter
            store: row.store
            appId: row.appId
        }
    }

    Rectangle {
        visible: row.showDivider
        anchors.bottom: parent.bottom
        x: MSpacing.md + (rankText.visible ? rankText.width + row.store.dp(12) : 0) + icon.width + row.store.dp(12)
        width: parent.width - x - MSpacing.md
        height: 1
        color: MColors.whiteOverlay04
    }
}
