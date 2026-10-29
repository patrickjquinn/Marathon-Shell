import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

Dialog {
    id: root

    property var app
    property alias hour: picker.hour
    property alias minute: picker.minute
    property alias second: secondSlider.value
    property int seconds: hour * 3600 + minute * 60 + second

    objectName: "timerDialog"
    canAccept: seconds > 0
    onAccepted: app.setTimer(seconds)

    Component.onCompleted: {
        const s = seconds;
        hour = Math.floor(s / 3600);
        minute = Math.floor(s % 3600 / 60);
        second = s % 60;
        seconds = Qt.binding(() => hour * 3600 + minute * 60 + second);
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Set")
                title: qsTr("Timer")
            }
            TimePicker {
                id: picker

                objectName: "timerPicker"
                anchors.horizontalCenter: parent.horizontalCenter
                hourMode: DateTime.TwentyFourHours

                Label {
                    anchors.centerIn: parent
                    text: Logic.formatCountdown(root.seconds)
                    font.pixelSize: Theme.fontSizeExtraLarge
                    font.features: ({
                            "tnum": 1
                        })
                    color: Theme.highlightColor
                }
            }
            Slider {
                id: secondSlider

                objectName: "secondSlider"
                width: parent.width
                label: qsTr("Seconds")
                minimumValue: 0
                maximumValue: 59
                stepSize: 1
                valueText: value
            }
        }

        VerticalScrollDecorator {}
    }
}
