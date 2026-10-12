pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick

Row {
    id: pageIndicator

    property int currentPage: 0
    property int totalPages: 1
    property bool showHubIcon: false
    property bool showTaskSwitcherIcon: false

    signal hubClicked
    signal taskSwitcherClicked

    spacing: Constants.spacingMedium

    Rectangle {
        visible: pageIndicator.showHubIcon
        width: Constants.iconSizeMedium
        height: Constants.iconSizeMedium
        radius: Constants.borderRadiusSmall
        color: pageIndicator.currentPage === -2 ? "#FFFFFF" : "#666666"

        GlyphIcon {
            name: "bell"
            size: Constants.iconSizeSmall
            anchors.centerIn: parent
            color: "white"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: pageIndicator.hubClicked()
        }
    }

    Rectangle {
        visible: pageIndicator.showTaskSwitcherIcon
        width: Constants.iconSizeMedium
        height: Constants.iconSizeMedium
        radius: Constants.borderRadiusSmall
        color: pageIndicator.currentPage === -1 ? "#FFFFFF" : "#666666"

        GlyphIcon {
            name: "layout-grid"
            size: Constants.iconSizeSmall
            anchors.centerIn: parent
            color: "black"
        }

        MouseArea {
            anchors.fill: parent
            onClicked: pageIndicator.taskSwitcherClicked()
        }
    }

    Repeater {
        model: pageIndicator.totalPages

        Rectangle {
            required property int index

            width: Constants.pageIndicatorSizeInactive / 2
            height: Constants.pageIndicatorSizeInactive / 2
            radius: Constants.pageIndicatorSizeInactive / 4
            color: index === pageIndicator.currentPage ? "#FFFFFF" : "#666666"
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }
    }
}
