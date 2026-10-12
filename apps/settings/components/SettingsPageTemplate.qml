pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Page {
    id: pageTemplate

    property string pageTitle: "Settings"
    property alias content: contentLoader.sourceComponent
    property bool showBackButton: true
    property bool overlayOpen: false

    signal navigateBack
    signal closeOverlayRequested

    Rectangle {
        id: header

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Constants.actionBarHeight
        color: MColors.surface
        z: 10
        visible: pageTemplate.showBackButton

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
                font.weight: MTypography.weightDemiBold
                font.family: MTypography.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            Accessible.role: Accessible.Button
            Accessible.name: "Back"
            Accessible.onPressAction: pageTemplate.navigateBack()
            onClicked: {
                HapticService.light();
                pageTemplate.navigateBack();
            }

            Rectangle {
                anchors.fill: parent
                color: MColors.textPrimary
                opacity: parent.pressed ? 0.1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: MMotion.fast
                    }
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: MColors.whiteOverlay08
        }
    }

    Loader {
        id: contentLoader

        anchors.top: pageTemplate.showBackButton ? header.bottom : parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    background: Rectangle {
        color: MColors.background
    }
}
