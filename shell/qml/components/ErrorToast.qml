import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

/**
 * ErrorToast - System-wide error notification
 *
 * Shows temporary error messages with icons and dismiss action
 * Auto-dismisses after 5 seconds or user can swipe away
 */
Item {
    id: errorToast
    anchors.fill: parent
    visible: false
    z: 2500 // Above everything except keyboard

    property string errorMessage: ""
    property string errorTitle: ""
    property string errorIcon: "alert-circle"
    property int displayDuration: 5000

    signal dismissed

    // Show error with message
    function show(title, message, icon) {
        errorTitle = title || "Error";
        errorMessage = message;
        errorIcon = icon || "alert-circle";
        visible = true;
        showAnimation.start();
        dismissTimer.restart();
        HapticService.medium();
        Logger.warn("ErrorToast", title + ": " + message);
    }

    // Hide error
    function hide() {
        hideAnimation.start();
    }

    // Auto-dismiss timer
    Timer {
        id: dismissTimer
        interval: errorToast.displayDuration
        onTriggered: errorToast.hide()
    }

    // Background overlay (tap to dismiss)
    MouseArea {
        anchors.fill: parent
        onClicked: errorToast.hide()
    }

    // Error card
    Rectangle {
        id: errorCard
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight + Constants.spacingLarge
        width: Math.min(parent.width - Constants.spacingXLarge, Math.round(400 * Constants.scaleFactor))
        height: errorContent.height + Constants.spacingLarge
        radius: Constants.borderRadiusLarge
        color: MColors.surface
        border.width: Constants.borderWidthMedium
        border.color: MColors.error
        opacity: 0

        // Glass morphism
        layer.enabled: true
        layer.effect: ShaderEffect {
            property real blur: 16
        }

        // Swipe down to dismiss
        MouseArea {
            id: swipeArea
            anchors.fill: parent
            drag.target: errorCard
            drag.axis: Drag.YAxis
            drag.minimumY: -errorCard.height
            drag.maximumY: 100

            onReleased: {
                if (errorCard.y > 50) {
                    // Swiped down far enough - dismiss
                    errorToast.hide();
                } else {
                    // Snap back
                    snapBackAnimation.start();
                }
            }

            // Prevent click-through
            onClicked: mouse.accepted = true
        }

        Column {
            id: errorContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Constants.spacingMedium
            spacing: Constants.spacingSmall

            // Header row
            Row {
                width: parent.width
                spacing: Constants.spacingMedium

                // Error icon
                Rectangle {
                    width: Constants.touchTargetSmall
                    height: Constants.touchTargetSmall
                    radius: Constants.borderRadiusSmall
                    color: Qt.rgba(MColors.error.r, MColors.error.g, MColors.error.b, 0.2)
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        name: errorToast.errorIcon
                        size: Constants.iconSizeMedium
                        color: MColors.error
                        anchors.centerIn: parent
                    }
                }

                // Title and close
                Column {
                    width: parent.width - Constants.touchTargetSmall - Constants.touchTargetMinimum - Constants.spacingMedium * 2
                    spacing: Constants.spacingXSmall
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: errorToast.errorTitle
                        color: MColors.text
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.DemiBold
                        font.family: MTypography.fontFamily
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "Tap to dismiss"
                        color: MColors.textTertiary
                        font.pixelSize: MTypography.sizeXSmall
                        font.family: MTypography.fontFamily
                    }
                }

                // Close button
                Rectangle {
                    width: Constants.touchTargetMinimum
                    height: Constants.touchTargetMinimum
                    radius: Constants.borderRadiusSmall
                    color: closeMouseArea.pressed ? MColors.elevated : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        name: "x"
                        size: Constants.iconSizeSmall
                        color: MColors.textSecondary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        id: closeMouseArea
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            errorToast.hide();
                        }
                    }
                }
            }

            // Error message
            Text {
                text: errorToast.errorMessage
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                width: parent.width
                wrapMode: Text.WordWrap
                visible: errorToast.errorMessage.length > 0
            }
        }
    }

    // Show animation
    ParallelAnimation {
        id: showAnimation

        NumberAnimation {
            target: errorCard
            property: "opacity"
            from: 0
            to: 1
            duration: 300
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: errorCard
            property: "y"
            from: -errorCard.height
            to: Constants.statusBarHeight + Constants.spacingLarge
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    // Hide animation
    SequentialAnimation {
        id: hideAnimation

        ParallelAnimation {
            NumberAnimation {
                target: errorCard
                property: "opacity"
                to: 0
                duration: 250
                easing.type: Easing.InQuad
            }

            NumberAnimation {
                target: errorCard
                property: "y"
                to: -errorCard.height
                duration: 300
                easing.type: Easing.InCubic
            }
        }

        ScriptAction {
            script: {
                errorToast.visible = false;
                errorToast.dismissed();
            }
        }
    }

    // Snap back animation (after partial swipe)
    NumberAnimation {
        id: snapBackAnimation
        target: errorCard
        property: "y"
        to: Constants.statusBarHeight + Constants.spacingLarge
        duration: 200
        easing.type: Easing.OutQuad
    }
}
