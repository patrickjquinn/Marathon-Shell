import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../ClockLogic.js" as Logic

TabItem {
    id: root

    property var app
    readonly property var countdown: app.countdown
    readonly property bool idle: !countdown.running && countdown.remaining === 0

    flickable: flick

    SilicaFlickable {
        id: flick

        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                objectName: "setTimer"
                text: qsTr("Set timer")
                enabled: !root.countdown.running
                onClicked: pageStack.push(Qt.resolvedUrl("TimerDialog.qml"), {
                    app: root.app,
                    seconds: Settings.get("clock/lastTimer", 600)
                })
            }
        }

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingLarge
            topPadding: Theme.paddingLarge * 2
            bottomPadding: Theme.paddingLarge

            ProgressCircle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Theme.itemSizeHuge * 2
                height: width
                value: root.countdown.total > 0 ? root.countdown.remaining / root.countdown.total : 0
                progressColor: Theme.highlightColor
                backgroundColor: Theme.rgba(Theme.primaryColor, 0.1)

                Label {
                    objectName: "timerTime"
                    anchors.centerIn: parent
                    text: Logic.formatCountdown(root.countdown.remaining)
                    font.pixelSize: Theme.fontSizeHuge
                    font.features: ({ "tnum": 1 })
                    color: root.countdown.running ? Theme.highlightColor : Theme.primaryColor
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                Button {
                    objectName: "startPause"
                    text: root.countdown.running ? qsTr("Pause") : qsTr("Start")
                    enabled: root.countdown.remaining > 0
                    onClicked: root.countdown.running ? root.countdown.pause() : root.countdown.start()
                }
                Button {
                    objectName: "reset"
                    text: qsTr("Reset")
                    enabled: root.countdown.total > 0
                    onClicked: root.countdown.reset()
                }
            }
            SectionHeader {
                visible: root.idle
                text: qsTr("Quick timers")
            }
            Grid {
                id: presets

                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: root.idle
                columns: 3
                spacing: Theme.paddingMedium

                Repeater {
                    objectName: "presets"
                    model: [1, 3, 5, 10, 15, 30]

                    Button {
                        required property int modelData

                        width: (presets.width - 2 * presets.spacing) / 3
                        text: qsTr("%n min", "", modelData)
                        onClicked: root.countdown.set(modelData * 60)
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
