import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects

Item {
    id: root

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
    height: 88
    clip: true

    Row {
        id: leftActionsRow
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: childrenRect.width
        visible: leftActions.length > 0

        Repeater {
            model: root.leftActions

            Rectangle {
                width: 80
                height: root.height
                color: modelData.color || MColors.success

                Icon {
                    anchors.centerIn: parent
                    name: modelData.icon || ""
                    size: 24
                    color: MColors.textOnAccent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.hapticEnabled)
                            MHaptics.medium();
                        root.leftActionTriggered(index);
                        resetPosition();
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
        visible: rightActions.length > 0

        Repeater {
            model: root.rightActions

            Rectangle {
                width: 80
                height: root.height
                color: modelData.color || MColors.error

                Icon {
                    anchors.centerIn: parent
                    name: modelData.icon || ""
                    size: 24
                    color: MColors.textOnAccent
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.hapticEnabled)
                            MHaptics.medium();
                        root.rightActionTriggered(index);
                        resetPosition();
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
                epsilon: MMotion.epsilon
            }
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            drag.target: contentContainer
            drag.axis: Drag.XAxis
            drag.minimumX: rightActions.length > 0 ? -rightActionsRow.width : 0
            drag.maximumX: leftActions.length > 0 ? leftActionsRow.width : 0

            property real startX: 0

            onPressed: function (mouse) {
                startX = contentContainer.x;
                root.swipeStarted();
            }

            onReleased: {
                var swipeDistance = contentContainer.x - startX;
                var absDistance = Math.abs(swipeDistance);

                if (absDistance > root.threshold) {
                    if (swipeDistance > 0 && leftActions.length > 0) {
                        contentContainer.x = leftActionsRow.width;
                        if (root.hapticEnabled)
                            MHaptics.light();
                    } else if (swipeDistance < 0 && rightActions.length > 0) {
                        contentContainer.x = -rightActionsRow.width;
                        if (root.hapticEnabled)
                            MHaptics.light();
                    } else {
                        resetPosition();
                    }
                } else {
                    resetPosition();
                }

                root.swipeFinished();
            }

            onCanceled: {
                resetPosition();
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
