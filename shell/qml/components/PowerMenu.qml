import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

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
    Accessible.name: qsTr("Power")

    // A choice: a glass ring with its label beneath.
    component PowerAction: Item {
        id: action

        property string iconName
        property string label
        property bool emphasised: false

        signal activated

        width: Silica.Theme.itemSizeExtraLarge
        height: ring.height + Silica.Theme.paddingMedium + actionLabel.height

        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()

        MCircularIconButton {
            id: ring

            anchors.horizontalCenter: parent.horizontalCenter
            width: Silica.Theme.itemSizeLarge
            height: width
            iconName: action.iconName
            iconSize: 24
            variant: action.emphasised ? "primary" : "secondary"
            onClicked: {
                HapticManager.medium();
                action.activated();
            }
        }
        Silica.Label {
            id: actionLabel

            anchors.top: ring.bottom
            anchors.topMargin: Silica.Theme.paddingMedium
            anchors.horizontalCenter: parent.horizontalCenter
            text: action.label
            font.pixelSize: Silica.Theme.fontSizeSmall
            color: action.emphasised ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
        }
    }

    // The frosted ambience behind the choices; a tap on it cancels.
    Item {
        id: backdrop

        anchors.fill: parent
        opacity: 0

        KeelAmbienceBackground {
            anchors.fill: parent
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
        }
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.pending = "";
                root.cancel();
            }
        }
    }

    Item {
        id: dialog

        anchors.fill: parent
        opacity: 0
        scale: 0.9

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Silica.Theme.horizontalPageMargin
            spacing: Silica.Theme.paddingLarge

            Silica.Label {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.pending === "reboot" ? qsTr("Restart phone?") : root.pending === "shutdown" ? qsTr("Power off phone?") : qsTr("Power")
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
            }

            Silica.Label {
                width: parent.width
                visible: root.pending !== ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.pending === "reboot" ? qsTr("Open apps will close.") : qsTr("You'll need to hold the power button to turn it back on.")
                color: Silica.Theme.secondaryHighlightColor
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: Silica.Theme.paddingLarge
                visible: root.pending === ""

                PowerAction {
                    iconName: "moon"
                    label: qsTr("Sleep")
                    emphasised: true
                    onActivated: {
                        root.sleepRequested();
                        root.hide();
                    }
                }
                PowerAction {
                    iconName: "rotate-ccw"
                    label: qsTr("Restart")
                    onActivated: root.pending = "reboot"
                }
                PowerAction {
                    iconName: "power"
                    label: qsTr("Power off")
                    onActivated: root.pending = "shutdown"
                }
            }

            PowerAction {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.pending !== ""
                iconName: root.pending === "reboot" ? "rotate-ccw" : "power"
                label: root.pending === "reboot" ? qsTr("Restart") : qsTr("Power off")
                emphasised: true
                onActivated: {
                    const action = root.pending;
                    root.hide();
                    if (action === "reboot")
                        root.rebootRequested();
                    else
                        root.shutdownRequested();
                }
            }

            Silica.Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Cancel")
                backgroundColor: "transparent"
                onClicked: {
                    HapticManager.light();
                    root.cancel();
                }
            }
        }
    }

    ParallelAnimation {
        id: fadeIn

        NumberAnimation {
            target: backdrop
            property: "opacity"
            to: 1
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
