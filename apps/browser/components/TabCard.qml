import MarathonApp.Browser
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

MCard {
    id: tabCard

    property var tabData: null
    property bool isCurrentTab: false

    signal tabClicked
    signal closeRequested

    height: Constants.cardHeight
    elevation: isCurrentTab ? 2 : 1
    interactive: false
    border.color: isCurrentTab ? MColors.accentBright : MColors.border
    onClicked: {
        tabCard.tabClicked();
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        onClicked: {
            tabCard.tabClicked();
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        anchors.rightMargin: MSpacing.md + Constants.touchTargetSmall
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
                anchors.right: parent.right
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

    Item {
        id: closeButtonContainer

        anchors.right: parent.right
        anchors.top: parent.top
        width: Constants.touchTargetSmall
        height: Constants.touchTargetSmall
        z: 1000

        MIconButton {
            anchors.centerIn: parent
            iconName: "x"
            enabled: false
            opacity: closeMouseArea.pressed ? 0.7 : 1
        }

        MouseArea {
            id: closeMouseArea

            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            propagateComposedEvents: false
            onPressed: mouse => {
                mouse.accepted = true;
            }
            onReleased: mouse => {
                mouse.accepted = true;
            }
            onDoubleClicked: mouse => {
                mouse.accepted = true;
            }
            onPressAndHold: mouse => {
                mouse.accepted = true;
            }
            onClicked: mouse => {
                mouse.accepted = true;
                tabCard.closeRequested();
            }
        }
    }
}
