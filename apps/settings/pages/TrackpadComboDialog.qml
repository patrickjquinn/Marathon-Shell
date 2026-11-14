import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

// A trackpad combination, swiped twice and confirmed with the PIN. The shell
// turns the swipes into strokes, the same way the lock screen reads them.
Dialog {
    id: dialog

    property string first: ""
    property alias pin: pinField.text
    readonly property bool confirming: first !== ""
    readonly property string strokes: Security.recordedCombo
    readonly property bool mismatch: confirming && strokes.length >= first.length && strokes !== first

    function restart() {
        Security.recordTrackpadCombo(false);
        Security.recordTrackpadCombo(true);
    }

    canAccept: confirming && strokes === first && pin.length >= 4
    onStatusChanged: if (status === PageStatus.Active)
        Security.recordTrackpadCombo(true)
    Component.onDestruction: Security.recordTrackpadCombo(false)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: qsTr("Trackpad unlock")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: dialog.confirming ? qsTr("Swipe the same combination again.") : qsTr("Swipe a combination of at least 4 strokes on the trackpad: up, down, left or right. To repeat a direction, pause between the swipes. On the lock screen, swipe it to unlock; your PIN always works too.")
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: Theme.itemSizeSmall
                spacing: Theme.paddingLarge

                Repeater {
                    model: dialog.strokes.length

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.paddingLarge
                        height: width
                        radius: width / 2
                        color: dialog.mismatch ? Theme.errorColor : Theme.highlightColor
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                horizontalAlignment: Text.AlignHCenter
                visible: dialog.mismatch
                color: Theme.errorColor
                text: qsTr("That isn't the same combination")
            }
            Button {
                objectName: "comboNext"
                anchors.horizontalCenter: parent.horizontalCenter
                text: dialog.confirming ? qsTr("Start again") : qsTr("Next")
                enabled: dialog.confirming || dialog.strokes.length >= 4
                onClicked: {
                    dialog.first = dialog.confirming ? "" : dialog.strokes;
                    dialog.restart();
                }
            }
            PasswordField {
                id: pinField

                objectName: "comboPinField"
                width: parent.width
                visible: dialog.confirming && dialog.strokes === dialog.first
                label: qsTr("Quick PIN")
                placeholderText: qsTr("Your quick PIN")
                inputMethodHints: Qt.ImhDigitsOnly
                EnterKey.enabled: dialog.canAccept
                EnterKey.onClicked: dialog.accept()
            }
        }
    }
}
