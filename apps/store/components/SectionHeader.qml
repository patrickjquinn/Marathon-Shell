import MarathonOS.Shell
import MarathonUI.Theme
import QtQuick

// Section title with an optional subtitle and an optional "See all" link.
Item {
    id: header

    property string title: ""
    property string subtitle: ""
    property string actionText: ""

    signal actionClicked

    implicitHeight: titleText.implicitHeight + (subtitle !== "" ? subtitleText.implicitHeight : 0)

    Text {
        id: titleText
        anchors.left: parent.left
        anchors.leftMargin: MSpacing.md
        anchors.right: actionLabel.left
        text: header.title
        color: MColors.textPrimary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeTitle3
        font.weight: Font.DemiBold
        font.letterSpacing: MTypography.trackingTitle3
        elide: Text.ElideRight
    }
    Text {
        id: subtitleText
        anchors.left: titleText.left
        anchors.top: titleText.bottom
        visible: header.subtitle !== ""
        text: header.subtitle
        color: MColors.textSecondary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeFootnote
    }
    Text {
        id: actionLabel
        anchors.right: parent.right
        anchors.rightMargin: MSpacing.md
        anchors.baseline: titleText.baseline
        visible: header.actionText !== ""
        text: header.actionText
        color: MColors.marathonTealBright
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeSubhead
        font.weight: Font.Medium

        MouseArea {
            anchors.fill: parent
            anchors.margins: -MSpacing.sm
            onClicked: {
                HapticService.light();
                header.actionClicked();
            }
        }
    }
}
