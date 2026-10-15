pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick

Column {
    id: pageIndicator

    required property real gridContentY
    required property real gridContentHeight
    required property real gridHeight
    property int pageCount: gridHeight > 0 ? Math.ceil(gridContentHeight / gridHeight) : 1
    property int currentPage: {
        if (gridContentY >= gridContentHeight - gridHeight - 1)
            return pageCount - 1;
        var page = Math.round(gridContentY / gridHeight);
        return Math.max(0, Math.min(page, pageCount - 1));
    }

    anchors.right: parent.right
    anchors.rightMargin: Constants.spacingMedium
    anchors.verticalCenter: parent.verticalCenter
    spacing: Constants.spacingSmall
    visible: pageCount > 1
    z: 100

    Repeater {
        model: pageIndicator.pageCount

        Rectangle {
            id: dot

            required property int index
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
