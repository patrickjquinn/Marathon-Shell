import MarathonOS.Shell
import MarathonUI.Theme
import QtQuick

// Brief confirmation with an optional action, typically Undo after a delete.
Rectangle {
    id: root

    property string text: ""
    property string actionText: ""
    property int timeout: 5000
    property bool open: false

    signal actionTriggered
    signal expired

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    function show(message, action) {
        text = message;
        actionText = action || "";
        open = true;
        hideTimer.restart();
    }

    function dismiss() {
        hideTimer.stop();
        open = false;
    }

    function trigger() {
        dismiss();
        actionTriggered();
    }

    implicitHeight: Math.round(56 * scaleFactor)
    radius: MRadius.md
    color: MColors.elev3
    border.width: 1
    border.color: MColors.border
    opacity: open ? 1 : 0
    visible: opacity > 0
    z: 900

    Accessible.role: Accessible.AlertMessage
    Accessible.name: text

    Behavior on opacity {
        enabled: !MMotion.reduceMotion

        NumberAnimation {
            duration: MMotion.fast
        }
    }

    Timer {
        id: hideTimer

        interval: root.timeout
        onTriggered: {
            root.open = false;
            root.expired();
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: MSpacing.md
        anchors.right: action.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: MColors.textPrimary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeBody
        elide: Text.ElideRight
    }

    Item {
        id: action

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.actionText.length > 0 ? actionLabel.implicitWidth + MSpacing.md * 2 : 0
        height: root.height
        visible: root.actionText.length > 0

        Accessible.role: Accessible.Button
        Accessible.name: root.actionText
        Accessible.onPressAction: root.trigger()

        Text {
            id: actionLabel

            anchors.centerIn: parent
            text: root.actionText
            color: MColors.accentBright
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeBody
            font.weight: MTypography.weightDemiBold
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.trigger()
        }
    }
}
