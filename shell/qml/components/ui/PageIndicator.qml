import QtQuick
import MarathonOS.Shell

Row {
    id: pageIndicator
    spacing: Constants.spacingMedium

    property int currentPage: 0
    property int totalPages: 1
    property bool showHubIcon: false
    property bool showTaskSwitcherIcon: false

    signal hubClicked
    signal taskSwitcherClicked

    Rectangle {
        visible: showHubIcon
        width: Constants.iconSizeMedium
        height: Constants.iconSizeMedium
        radius: Constants.borderRadiusSmall
        color: currentPage === -2 ? "#FFFFFF" : "#666666"

        Image {
            source: "qrc:/images/icons/lucide/bell.svg"
            width: Constants.iconSizeSmall
            height: Constants.iconSizeSmall
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }

        MouseArea {
            anchors.fill: parent
            onClicked: hubClicked()
        }
    }

    Rectangle {
        visible: showTaskSwitcherIcon
        width: Constants.iconSizeMedium
        height: Constants.iconSizeMedium
        radius: Constants.borderRadiusSmall
        color: currentPage === -1 ? "#FFFFFF" : "#666666"

        Image {
            source: "qrc:/images/icons/lucide/grid.svg"
            width: Constants.iconSizeSmall
            height: Constants.iconSizeSmall
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }

        MouseArea {
            anchors.fill: parent
            onClicked: taskSwitcherClicked()
        }
    }

    Repeater {
        model: totalPages

        Rectangle {
            width: Constants.pageIndicatorSizeInactive / 2
            height: Constants.pageIndicatorSizeInactive / 2
            radius: Constants.pageIndicatorSizeInactive / 4
            color: index === currentPage ? "#FFFFFF" : "#666666"
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }
    }
}
