import MarathonUI.Theme
import QtQuick

Column {
    id: pageIndicator

    required property int taskCount
    required property real gridContentY
    required property real gridHeight
    property int pageCount: Math.ceil(taskCount / 4)
    property int currentPage: {
        var page = Math.round(gridContentY / gridHeight);
        return Math.max(0, Math.min(page, pageCount - 1));
    }

    anchors.right: parent.right
    anchors.rightMargin: Constants.spacingMedium
    anchors.verticalCenter: parent.verticalCenter
    spacing: Constants.spacingSmall
    visible: taskCount > 4
    z: 100

    Repeater {
        model: pageIndicator.pageCount

        Rectangle {
            id: dot

            property bool isActive: index === pageIndicator.currentPage

            width: 6
            height: isActive ? 20 : 6
            radius: 3
            color: isActive ? MColors.accent : Qt.rgba(255, 255, 255, 0.4)
            layer.enabled: true
            layer.effect: null

            Behavior on height {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }
        }
    }
}
