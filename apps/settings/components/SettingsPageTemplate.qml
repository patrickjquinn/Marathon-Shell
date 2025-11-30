import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Page {
    id: pageTemplate

    property string pageTitle: "Settings"
    property alias content: contentLoader.sourceComponent
    property bool showBackButton: true

    signal navigateBack

    background: Rectangle {
        color: MColors.background
    }

    // Header with back button (BB10 style)
    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Constants.actionBarHeight
        color: MColors.surface
        z: 10
        visible: showBackButton

        Row {
            anchors.left: parent.left
            anchors.leftMargin: MSpacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: MSpacing.md

            Icon {
                name: "chevron-down"
                size: Constants.iconSizeMedium
                color: MColors.textPrimary
                anchors.verticalCenter: parent.verticalCenter
                rotation: 90
            }

            Text {
                text: pageTemplate.pageTitle
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeBody
                font.weight: Font.DemiBold
                font.family: MTypography.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                HapticService.light();
                pageTemplate.navigateBack();
            }

            // Press feedback
            Rectangle {
                anchors.fill: parent
                color: MColors.textPrimary
                opacity: parent.pressed ? 0.1 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }
        }

        // Bottom border
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(255, 255, 255, 0.08)
        }
    }

    // Content area
    Loader {
        id: contentLoader
        anchors.top: showBackButton ? header.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}
