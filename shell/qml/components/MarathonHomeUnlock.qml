pragma ComponentBehavior: Bound

import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// The lock screen's PIN pad on the boot splash's black, under the Marathon
// mark: the PIN that opens the encrypted /home. It rises out of Plymouth's
// frame and, once a PIN opens /home, settles back into it for Plymouth.
Item {
    id: root

    // submit(pin), busy, rejected(), opened(), release(): HomeUnlock (homeunlock.h).
    required property QtObject unlock
    property string pin: ""
    property string error: ""
    // 0: Plymouth's frame; 1: the pad.
    property real lift: 0

    // MarathonPinScreen's sizes, compact on short or square screens.
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800
    readonly property real compactUnit: Constants.screenHeight / 720 / Constants.scaleFactor
    readonly property real keyButtonSize: compactLayout ? Math.round(72 * compactUnit) : 64
    readonly property real keyCellPadding: compactLayout ? 6 * compactUnit : 12
    readonly property real cellSize: Math.round(keyButtonSize * Constants.scaleFactor) + Math.round(keyCellPadding * Constants.scaleFactor)
    readonly property real rowSpacing: Math.round((compactLayout ? 6 * compactUnit : 12) * Constants.scaleFactor)
    readonly property real columnSpacing: Math.round((compactLayout ? 14 * compactUnit : 16) * Constants.scaleFactor)
    readonly property int digitSize: compactLayout ? Math.round(28 * compactUnit) : 28
    readonly property int glyphSize: compactLayout ? Math.round(24 * compactUnit) : 24

    // A quick PIN is 4-6 digits; only the 6th submits by itself.
    function type(digit) {
        if (pin.length >= 6 || unlock.busy)
            return;
        pin += digit;
        error = "";
        if (pin.length === 6)
            submit();
    }

    function submit() {
        if (pin.length >= 4)
            unlock.submit(pin);
    }

    Connections {
        function onRejected() {
            root.pin = "";
            root.error = qsTr("Wrong PIN. Try again");
        }

        function onOpened() {
            settle.start();
        }

        target: root.unlock
    }

    NumberAnimation on lift {
        to: 1
        duration: MMotion.ms(MMotion.slow)
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: settle

        target: root
        property: "lift"
        to: 0
        duration: MMotion.ms(MMotion.slow)
        easing.type: Easing.InOutCubic
        onFinished: root.unlock.release()
    }

    // The splash's logo becomes a key's disc above the pad.
    MarathonBootSplash {
        readonly property real disc: Math.round(root.keyButtonSize * Constants.scaleFactor)
        readonly property real logo: Math.round(disc * 200 / 96)

        anchors.fill: parent
        deviceScale: PlymouthScale
        chromeOpacity: 1 - root.lift
        logoOpacity: root.compactLayout ? 1 - root.lift : 1
        lift: root.compactLayout ? 0 : root.lift
        liftTarget: Qt.rect((root.width - logo) / 2, pad.y - pad.spacing - (disc + logo) / 2, logo, logo)
    }

    // Where MarathonPinScreen puts it, so the lock screen's pad lands on this one.
    Column {
        id: pad

        opacity: root.lift
        enabled: root.lift === 1
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.compactLayout ? Math.round((Constants.statusBarHeight - Constants.navBarHeight - Silica.Theme.itemSizeSmall) / 2) : Math.round(-20 * Constants.scaleFactor)
        spacing: Math.round((root.compactLayout ? 8 * root.compactUnit : 24) * Constants.scaleFactor)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("Enter PIN")
            color: Silica.Theme.highlightColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeLarge
            renderType: Text.QtRendering
        }

        // A dot per digit, backspace at the end.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(keypad.width, Math.round((6 * 14 + 5 * 16 + 2 * (root.keyButtonSize + root.keyCellPadding)) * Constants.scaleFactor))
            height: Math.round(root.keyButtonSize * (root.compactLayout ? 0.7 : 1) * Constants.scaleFactor)

            Row {
                anchors.centerIn: parent
                spacing: Math.round(16 * Constants.scaleFactor)
                Accessible.role: Accessible.StaticText
                Accessible.name: root.pin.length + " digits entered"

                Repeater {
                    model: root.pin.length

                    Rectangle {
                        width: Math.round(14 * Constants.scaleFactor)
                        height: width
                        radius: width / 2
                        color: Silica.Theme.highlightColor
                        antialiasing: true
                    }
                }
            }

            Silica.BusyIndicator {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: Silica.BusyIndicatorSize.Small
                running: root.unlock.busy
                visible: running
            }

            MCircularIconButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "backspace"
                iconSize: root.glyphSize
                buttonSize: root.keyButtonSize
                variant: "secondary"
                iconColor: MColors.textSecondary
                //: Accessible name of the PIN pad delete key
                a11yName: qsTr("Delete")
                visible: root.pin.length > 0 && !root.unlock.busy
                onClicked: {
                    root.pin = root.pin.slice(0, -1);
                    root.error = "";
                }
            }
        }

        // Two lines held, so an error never moves the keypad.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 2 * Silica.Theme.paddingLarge
            height: Math.ceil(fontMetrics.height * 2)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: root.error
            color: Silica.Theme.errorColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeSmall
            renderType: Text.QtRendering

            FontMetrics {
                id: fontMetrics

                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeSmall
            }
        }

        Grid {
            id: keypad

            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            columnSpacing: root.columnSpacing
            rowSpacing: root.rowSpacing

            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "accept"]

                delegate: Item {
                    id: cell

                    required property string modelData

                    width: root.cellSize
                    height: root.cellSize

                    MCircularIconButton {
                        anchors.centerIn: parent
                        visible: cell.modelData !== ""
                        text: cell.modelData === "accept" ? "" : cell.modelData
                        iconName: cell.modelData === "accept" ? "check" : ""
                        iconSize: cell.modelData === "accept" ? root.glyphSize : root.digitSize
                        buttonSize: root.keyButtonSize
                        // The whole cell and half the gap, so a near miss still lands.
                        hitMargin: (cell.width - diameter + Math.min(keypad.columnSpacing, keypad.rowSpacing)) / 2
                        variant: cell.modelData === "accept" && !disabled ? "primary" : "secondary"
                        textColor: MColors.textPrimary
                        disabled: root.unlock.busy || (cell.modelData === "accept" && root.pin.length < 4)
                        a11yName: cell.modelData === "accept" ? qsTr("Unlock") : text
                        onClicked: cell.modelData === "accept" ? root.submit() : root.type(cell.modelData)
                    }
                }
            }
        }
    }
}
