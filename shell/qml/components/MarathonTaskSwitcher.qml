import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon Active Frames task switcher.
//
// Replaces the deleted MarathonActiveFramesHome.qml's "switcher" mode
// with a focused, gesture-only overlay. Bound to TaskModel — each
// running app shows as a card; tap to switch, X to close, tap the
// scrim or swipe down to dismiss.
//
// Visibility is driven by the shell (`active` property). The shell
// shows this when long-swipe-up fires with at least one running app;
// long-swipe-up with zero tasks is a no-op per the gesture handler.
Item {
    id: switcher

    property bool active: false

    signal switchTo(string appId)
    signal closeApp(string appId)
    signal dismissed

    anchors.fill: parent
    visible: opacity > 0.001
    opacity: active ? 1 : 0
    z: Constants.zIndexTaskSwitcher

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    // Scrim — dim the wallpaper below, tap to dismiss.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: switcher.dismissed()
        }
    }

    // Header — page title + count.
    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.statusBarHeight + Math.round(20 * Constants.scaleFactor)
        height: Math.round(40 * Constants.scaleFactor)

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Math.round(20 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            text: "Active Frames"
            color: MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeTitle3
            font.weight: MTypography.weightExtraLight
            font.letterSpacing: MTypography.trackingTitle3
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Math.round(20 * Constants.scaleFactor)
            anchors.verticalCenter: parent.verticalCenter
            text: TaskModel.taskCount + (TaskModel.taskCount === 1 ? " app" : " apps")
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
        }
    }

    // 2×N grid of running apps.
    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: Math.round(8 * Constants.scaleFactor)
        anchors.bottomMargin: Constants.navBarHeight + Math.round(16 * Constants.scaleFactor)
        contentHeight: grid.implicitHeight + Math.round(40 * Constants.scaleFactor)
        clip: true

        Grid {
            id: grid

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
            anchors.rightMargin: Math.round(16 * Constants.scaleFactor)
            columns: 2
            columnSpacing: Math.round(12 * Constants.scaleFactor)
            rowSpacing: Math.round(12 * Constants.scaleFactor)

            readonly property real cellWidth: (width - columnSpacing) / 2
            readonly property real cellHeight: Math.round(cellWidth * 1.35)

            Repeater {
                model: TaskModel

                Rectangle {
                    id: card

                    required property int index
                    required property string appId
                    required property string title
                    required property string icon

                    width: grid.cellWidth
                    height: grid.cellHeight
                    radius: MRadius.lg
                    color: MColors.surface
                    border.width: 1
                    border.color: MColors.borderSubtle
                    clip: true
                    scale: cardSwipe.pressed ? 0.97 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: MMotion.micro
                            easing.type: Easing.OutCubic
                        }
                    }

                    // Header — icon, app name, close button.
                    Item {
                        id: cardHeader

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Math.round(8 * Constants.scaleFactor)
                        height: Math.round(28 * Constants.scaleFactor)

                        Rectangle {
                            id: iconChip

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.height
                            height: parent.height
                            radius: MRadius.sm
                            color: MColors.whiteOverlay08

                            Icon {
                                anchors.centerIn: parent
                                name: card.icon || "square"
                                size: Math.round(14 * Constants.scaleFactor)
                                color: MColors.textPrimary
                            }
                        }

                        Text {
                            anchors.left: iconChip.right
                            anchors.leftMargin: Math.round(8 * Constants.scaleFactor)
                            anchors.right: closeBtn.left
                            anchors.rightMargin: Math.round(8 * Constants.scaleFactor)
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.title || card.appId
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            font.weight: MTypography.weightMedium
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: closeBtn

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.height
                            height: parent.height
                            radius: width / 2
                            color: closeMouseArea.pressed ? MColors.whiteOverlay16 : MColors.whiteOverlay08

                            Icon {
                                anchors.centerIn: parent
                                name: "x"
                                size: Math.round(12 * Constants.scaleFactor)
                                color: MColors.textPrimary
                            }

                            MouseArea {
                                id: closeMouseArea

                                anchors.fill: parent
                                onClicked: {
                                    HapticManager.light();
                                    switcher.closeApp(card.appId);
                                }
                            }
                        }
                    }

                    // Preview area — placeholder tint plus the app icon
                    // as a watermark. Wayland live-surface thumbnails are
                    // a follow-up (TaskModel.SnapshotRole isn't yet
                    // wired for native runner apps).
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: cardHeader.bottom
                        anchors.bottom: parent.bottom
                        anchors.margins: Math.round(8 * Constants.scaleFactor)
                        radius: MRadius.md
                        color: MColors.elev1

                        Icon {
                            anchors.centerIn: parent
                            name: card.icon || "layout-grid"
                            size: Math.round(44 * Constants.scaleFactor)
                            color: MColors.textTertiary
                            opacity: 0.4
                        }
                    }

                    // Swipe-up-to-close gesture, plus tap-to-switch.
                    MouseArea {
                        id: cardSwipe

                        property real startY: 0
                        property real currentY: 0
                        property bool swipedClose: false

                        anchors.fill: parent
                        preventStealing: false
                        onPressed: function (mouse) {
                            startY = mouse.y;
                            currentY = mouse.y;
                            swipedClose = false;
                        }
                        onPositionChanged: function (mouse) {
                            currentY = mouse.y;
                            const dy = startY - currentY;
                            if (dy > Math.round(80 * Constants.scaleFactor) && !swipedClose) {
                                swipedClose = true;
                                HapticManager.medium();
                                switcher.closeApp(card.appId);
                            }
                        }
                        onClicked: {
                            if (swipedClose)
                                return;
                            HapticManager.light();
                            switcher.switchTo(card.appId);
                        }
                    }
                }
            }
        }
    }

    // Empty state — long-swipe-up with no running apps shows this.
    Column {
        anchors.centerIn: parent
        spacing: Math.round(12 * Constants.scaleFactor)
        visible: TaskModel.taskCount === 0

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "layers"
            size: Math.round(64 * Constants.scaleFactor)
            color: MColors.textTertiary
            opacity: 0.5
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No active apps"
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeBody
            font.weight: MTypography.weightMedium
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Open an app to see it here"
            color: MColors.textTertiary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
        }
    }
}
