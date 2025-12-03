import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Containers

MCard {
    id: tabCard
    height: Constants.cardHeight
    elevation: isCurrentTab ? 2 : 1
    interactive: false // Disable built-in MouseArea to allow custom z-ordering

    signal tabClicked
    signal closeRequested

    property var tabData: null
    property bool isCurrentTab: false

    border.color: isCurrentTab ? MColors.accentBright : MColors.border

    onClicked: {
        tabCard.tabClicked();
    }

    // Manual MouseArea for tab clicking, placed behind content but filling card
    MouseArea {
        anchors.fill: parent
        z: 0 // Bottom layer
        onClicked: {
            tabCard.tabClicked();
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        anchors.rightMargin: MSpacing.md + Constants.touchTargetSmall // Make room for close button
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
        z: 1000 // High z-index to sit above card content

        MIconButton {
            anchors.centerIn: parent
            iconName: "x"
            // Disable internal mouse handling to prevent conflicts, we handle it manually
            enabled: false 
            opacity: closeMouseArea.pressed ? 0.7 : 1.0 // Visual feedback
            // color property removed as it caused a crash
        }

        MouseArea {
            id: closeMouseArea
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            propagateComposedEvents: false

            // Explicitly accept all events to prevent propagation to MCard
            onPressed: (mouse) => { mouse.accepted = true; }
            onReleased: (mouse) => { mouse.accepted = true; }
            onDoubleClicked: (mouse) => { mouse.accepted = true; }
            onPressAndHold: (mouse) => { mouse.accepted = true; }

            onClicked: (mouse) => {
                mouse.accepted = true;
                tabCard.closeRequested();
            }
        }
    }
}
