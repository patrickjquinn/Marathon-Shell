import MarathonOS.Shell 1.0
import MarathonUI.Core
import QtQuick

Item {
    id: root

    property bool showing: false
    // "" | "reboot" | "shutdown" — a destructive choice waits here for confirmation.
    property string pending: ""

    signal sleepRequested
    signal rebootRequested
    signal shutdownRequested
    signal canceled

    function show() {
        pending = "";
        showing = true;
        visible = true;
        HapticManager.medium();
        fadeOut.stop();
        fadeIn.start();
    }

    function hide() {
        showing = false;
        fadeIn.stop();
        fadeOut.start();
    }

    function cancel() {
        if (pending !== "") {
            pending = "";
            return;
        }
        canceled();
        hide();
    }

    anchors.fill: parent
    visible: false
    enabled: showing
    z: Constants.zIndexModal + 100

    Accessible.role: Accessible.Dialog
    Accessible.name: "Power"

    component PowerRow: Rectangle {
        id: row

        property string iconName
        property string label
        property bool primary: false
        property bool destructive: false

        signal activated

        width: parent.width
        height: Math.round(56 * Constants.scaleFactor)
        radius: MRadius.md
        color: {
            if (primary)
                return rowMouse.pressed ? MColors.marathonTealDark : MColors.marathonTeal;
            if (destructive)
                return rowMouse.pressed ? MColors.errorDim : MColors.error;
            return rowMouse.pressed ? MColors.bb10Elevated : MColors.bb10Card;
        }
        border.width: primary || destructive ? 0 : Math.max(1, Math.round(Constants.scaleFactor))
        border.color: MColors.border
        scale: rowMouse.pressed && !MMotion.reduceMotion ? 0.97 : 1

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()

        Row {
            anchors.left: parent.left
            anchors.leftMargin: MSpacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: MSpacing.md

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: row.iconName
                size: Math.round(24 * Constants.scaleFactor)
                color: row.primary ? MColors.textOnAccent : MColors.textPrimary
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: row.label
                font.pixelSize: MTypography.sizeBody
                font.weight: row.primary || row.destructive ? MTypography.weightDemiBold : MTypography.weightMedium
                font.family: MTypography.fontFamily
                color: row.primary ? MColors.textOnAccent : MColors.textPrimary
            }
        }

        MouseArea {
            id: rowMouse

            anchors.fill: parent
            onClicked: {
                HapticManager.medium();
                row.activated();
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: MMotion.micro
            }
        }
    }

    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: MColors.bb10Black
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.pending = "";
                root.cancel();
            }
        }
    }

    Rectangle {
        id: dialog

        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, Math.round(360 * Constants.scaleFactor))
        height: contentColumn.height + MSpacing.lg * 2
        radius: MRadius.lg
        color: MColors.elev2
        border.width: Math.max(1, Math.round(Constants.scaleFactor))
        border.color: MColors.border
        layer.enabled: true
        opacity: 0
        scale: 0.9

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: contentColumn

            anchors.centerIn: parent
            width: parent.width - MSpacing.lg * 2
            spacing: MSpacing.sm

            Text {
                width: parent.width
                text: root.pending === "reboot" ? "Restart phone?" : root.pending === "shutdown" ? "Power off phone?" : "Power"
                font.pixelSize: MTypography.sizeLarge
                font.weight: MTypography.weightDemiBold
                font.family: MTypography.fontFamily
                color: MColors.textPrimary
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                width: parent.width
                visible: root.pending !== ""
                text: root.pending === "reboot" ? "Open apps will close." : "You'll need to hold the power button to turn it back on."
                wrapMode: Text.Wrap
                font.pixelSize: MTypography.sizeSubhead
                font.family: MTypography.fontFamily
                color: MColors.textSecondary
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                width: 1
                height: MSpacing.sm
            }

            PowerRow {
                visible: root.pending === ""
                iconName: "moon"
                label: "Sleep"
                primary: true
                onActivated: {
                    root.sleepRequested();
                    root.hide();
                }
            }

            PowerRow {
                visible: root.pending === ""
                iconName: "rotate-ccw"
                label: "Restart"
                onActivated: root.pending = "reboot"
            }

            PowerRow {
                visible: root.pending === ""
                iconName: "power"
                label: "Power off"
                onActivated: root.pending = "shutdown"
            }

            PowerRow {
                visible: root.pending !== ""
                iconName: root.pending === "reboot" ? "rotate-ccw" : "power"
                label: root.pending === "reboot" ? "Restart" : "Power off"
                destructive: true
                onActivated: {
                    const action = root.pending;
                    root.hide();
                    if (action === "reboot")
                        root.rebootRequested();
                    else
                        root.shutdownRequested();
                }
            }

            Item {
                width: 1
                height: MSpacing.sm
            }

            Item {
                width: parent.width
                height: Math.round(44 * Constants.scaleFactor)

                Accessible.role: Accessible.Button
                Accessible.name: "Cancel"
                Accessible.onPressAction: root.cancel()

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: MTypography.sizeBody
                    font.weight: MTypography.weightMedium
                    font.family: MTypography.fontFamily
                    color: cancelMouse.pressed ? MColors.textPrimary : MColors.textSecondary
                }

                MouseArea {
                    id: cancelMouse

                    anchors.fill: parent
                    onClicked: {
                        HapticManager.light();
                        root.cancel();
                    }
                }
            }
        }
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: backdrop
            property: "opacity"
            to: 0.7
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: dialog
            property: "opacity"
            to: 1
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: dialog
            property: "scale"
            to: 1
            duration: MMotion.reduceMotion ? 0 : MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: fadeOut

        ParallelAnimation {
            NumberAnimation {
                target: backdrop
                property: "opacity"
                to: 0
                duration: MMotion.fast
                easing.type: Easing.InCubic
            }

            NumberAnimation {
                target: dialog
                property: "opacity"
                to: 0
                duration: MMotion.fast
                easing.type: Easing.InCubic
            }

            NumberAnimation {
                target: dialog
                property: "scale"
                to: 0.9
                duration: MMotion.reduceMotion ? 0 : MMotion.fast
                easing.type: Easing.InCubic
            }
        }

        PropertyAction {
            target: root
            property: "visible"
            value: false
        }
    }
}
