import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Containers

MCard {
    id: tabCard
    height: Constants.cardHeight
    elevation: isCurrentTab ? 2 : 1
    interactive: true

    signal tabClicked
    signal closeRequested

    property var tabData: null
    property bool isCurrentTab: false

    border.color: isCurrentTab ? MColors.accentBright : MColors.border

    onClicked: {
        tabCard.tabClicked();
    }

    Column {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        spacing: MSpacing.sm

        Item {
            width: parent.width
            height: Constants.touchTargetSmall

            Icon {
                id: globeIcon
                anchors.left: parent.left
                anchors.top: parent.top
                name: "globe"
                size: Constants.iconSizeSmall
                color: isCurrentTab ? MColors.accentBright : MColors.textSecondary
            }

            Column {
                anchors.left: globeIcon.right
                anchors.leftMargin: MSpacing.sm
                anchors.right: closeButton.left
                anchors.rightMargin: MSpacing.sm
                anchors.top: parent.top
                spacing: 2

                Text {
                    width: parent.width
                    text: tabData ? (tabData.title || "New Tab") : "New Tab"
                    font.pixelSize: MTypography.sizeBody
                    font.weight: Font.DemiBold
                    font.family: MTypography.fontFamily
                    color: isCurrentTab ? MColors.text : MColors.textSecondary
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: tabData ? (tabData.url || "about:blank") : "about:blank"
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                    color: MColors.textTertiary
                    elide: Text.ElideMiddle
                }
            }

            MIconButton {
                id: closeButton
                anchors.right: parent.right
                anchors.top: parent.top
                iconName: "x"

                onClicked: {
                    tabCard.closeRequested();
                }
            }
        }

        Rectangle {
            width: parent.width
            height: parent.height - Constants.touchTargetSmall - MSpacing.sm
            radius: Constants.borderRadiusSmall
            color: MColors.background
            border.width: Constants.borderWidthThin
            border.color: MColors.border
            clip: true

            Text {
                anchors.centerIn: parent
                text: tabData ? (tabData.title || tabData.url || "Loading...") : "Loading..."
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                color: MColors.textTertiary
            }
        }
    }
}
