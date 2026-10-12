pragma ComponentBehavior: Bound

import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Effects

Item {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property alias contentItem: contentContainer.data
    property list<QtObject> leftActions
    property list<QtObject> rightActions
    property real threshold: width * 0.3
    property bool hapticEnabled: true

    signal leftActionTriggered(int index)
    signal rightActionTriggered(int index)
    signal swipeStarted
    signal swipeFinished

    width: parent.width
    height: Math.round(88 * scaleFactor)
    clip: true

    Row {
        id: leftActionsRow
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: childrenRect.width
        visible: root.leftActions.length > 0

        Repeater {
            model: root.leftActions

            Rectangle {
                id: leftAction

                required property var modelData
                required property int index

                width: Math.round(80 * root.scaleFactor)
                height: root.height
                color: modelData.color || MColors.success

                Icon {
                    anchors.centerIn: parent
                    name: leftAction.modelData.icon || ""
                    size: Math.round(24 * root.scaleFactor)
                    color: MColors.textOnAccent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.hapticEnabled)
                            MHaptics.medium();
                        root.leftActionTriggered(leftAction.index);
                        root.resetPosition();
                    }
                }
            }
        }
    }

    Row {
        id: rightActionsRow
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: childrenRect.width
        layoutDirection: Qt.RightToLeft
        visible: root.rightActions.length > 0

        Repeater {
            model: root.rightActions

            Rectangle {
                id: rightAction

                required property var modelData
                required property int index

                width: Math.round(80 * root.scaleFactor)
                height: root.height
                color: modelData.color || MColors.error

                Icon {
                    anchors.centerIn: parent
                    name: rightAction.modelData.icon || ""
                    size: Math.round(24 * root.scaleFactor)
                    color: MColors.textOnAccent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.hapticEnabled)
                            MHaptics.medium();
                        root.rightActionTriggered(rightAction.index);
                        root.resetPosition();
                    }
                }
            }
        }
    }

    Rectangle {
        id: contentContainer
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.width
        x: 0
        color: MColors.bb10Black

        Behavior on x {
            enabled: !dragArea.drag.active
            SpringAnimation {
                spring: MMotion.springHeavy
                damping: MMotion.dampingHeavy
                epsilon: MMotion.epsilonSpatial
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            drag.target: contentContainer
            drag.axis: Drag.XAxis
            drag.minimumX: root.rightActions.length > 0 ? -rightActionsRow.width : 0
            drag.maximumX: root.leftActions.length > 0 ? leftActionsRow.width : 0

            property real startX: 0

            onPressed: function (mouse) {
                startX = contentContainer.x;
                root.swipeStarted();
            }

            onReleased: {
                var swipeDistance = contentContainer.x - startX;
                var absDistance = Math.abs(swipeDistance);

                if (absDistance > root.threshold) {
                    if (swipeDistance > 0 && root.leftActions.length > 0) {
                        contentContainer.x = leftActionsRow.width;
                        if (root.hapticEnabled)
                            MHaptics.light();
                    } else if (swipeDistance < 0 && root.rightActions.length > 0) {
                        contentContainer.x = -rightActionsRow.width;
                        if (root.hapticEnabled)
                            MHaptics.light();
                    } else {
                        root.resetPosition();
                    }
                } else {
                    root.resetPosition();
                }

                root.swipeFinished();
            }

            onCanceled: {
                root.resetPosition();
                root.swipeFinished();
            }
        }
    }

    function resetPosition() {
        contentContainer.x = 0;
    }

    function revealLeftActions() {
        if (leftActions.length > 0) {
            contentContainer.x = leftActionsRow.width;
            if (hapticEnabled)
                MHaptics.light();
        }
    }

    function revealRightActions() {
        if (rightActions.length > 0) {
            contentContainer.x = -rightActionsRow.width;
            if (hapticEnabled)
                MHaptics.light();
        }
    }
}
