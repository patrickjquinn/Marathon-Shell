import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: modal
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.7)
    visible: false
    opacity: 0
    z: 2000

    property alias title: modalTitle.text
    default property alias content: contentArea.children

    signal closed

    function open() {
        visible = true;
        openAnimation.start();
    }

    function close() {
        closeAnimation.start();
    }

    NumberAnimation {
        id: openAnimation
        target: modal
        property: "opacity"
        from: 0
        to: 1
        duration: Constants.animationDurationNormal
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: closeAnimation
        NumberAnimation {
            target: modal
            property: "opacity"
            from: 1
            to: 0
            duration: Constants.animationDurationFast
            easing.type: Easing.InCubic
        }
        PropertyAction {
            target: modal
            property: "visible"
            value: false
        }
        ScriptAction {
            script: modal.closed()
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: modal.close()
        z: 1
    }

    Rectangle {
        id: modalCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 500)
        height: Math.min(modalColumn.height + MSpacing.touchTargetLarge, parent.height - 128)
        color: Qt.rgba(15, 15, 15, 0.98)
        radius: MRadius.md
        z: 2
        border.width: 1
        border.color: MColors.border

        // Inner glow
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.02)
        }

        Column {
            id: modalColumn
            anchors.fill: parent
            anchors.margins: MSpacing.xl
            spacing: MSpacing.lg

            Item {
                id: modalHeader
                width: parent.width
                height: MSpacing.touchTargetMedium

                Text {
                    id: modalTitle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightBold
                    font.family: MTypography.fontFamily
                    width: parent.width - MSpacing.touchTargetMedium - MSpacing.sm
                }

                MIconButton {
                    iconName: "x"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        Logger.info("Modal", "Close button clicked");
                        modal.close();
                    }
                }
            }

            Item {
                id: contentArea
                width: parent.width
                height: childrenRect.height
            }
        }

        MouseArea {
            anchors.fill: parent
            z: 5
            onClicked: {
                console.log("Modal card clicked (blocking background)");
            }
        }
    }
}
