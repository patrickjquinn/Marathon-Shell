import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

TabItem {
    id: root

    property var app
    property real topMargin
    readonly property var stopwatch: app.stopwatch
    readonly property var splits: Logic.lapSplits(stopwatch.laps)
    readonly property real lastLap: stopwatch.laps.length > 0 ? stopwatch.laps[stopwatch.laps.length - 1] : 0

    flickable: list

    InfoLabel {
        objectName: "stopwatchHint"
        y: parent.height / 3 - height / 2
        visible: !root.stopwatch.running && root.stopwatch.elapsed === 0
        text: qsTr("Tap below to start the stopwatch")
    }

    // Bottom-up, so the newest lap sits just above the running one, as in Jolla Clock.
    SilicaListView {
        id: list

        anchors.fill: parent
        verticalLayoutDirection: ListView.BottomToTop
        model: root.splits.slice().reverse()

        header: Item {
            width: list.width
            height: current.height + Theme.paddingLarge * 2

            IconButton {
                objectName: "startLap"
                anchors.left: parent.left
                anchors.leftMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: current.verticalCenter
                icon.source: root.stopwatch.running ? "image://theme/icon-l-add" : "image://theme/icon-l-play"
                Accessible.name: root.stopwatch.running ? qsTr("Lap") : qsTr("Start")
                onClicked: root.stopwatch.running ? root.stopwatch.lap() : root.stopwatch.start()
            }
            Column {
                id: current

                y: Theme.paddingLarge
                anchors.horizontalCenter: parent.horizontalCenter

                LapTime {
                    objectName: "lapTime"
                    time: root.stopwatch.elapsed - root.lastLap
                    caption: qsTr("Lap")
                    color: Theme.highlightColor
                }
                LapTime {
                    objectName: "stopwatchTime"
                    time: root.stopwatch.elapsed
                    caption: qsTr("Total")
                    color: Theme.primaryColor
                }
            }
            IconButton {
                objectName: "pauseReset"
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: current.verticalCenter
                enabled: root.stopwatch.running || root.stopwatch.elapsed > 0
                icon.source: root.stopwatch.running ? "image://theme/icon-l-pause" : "image://theme/icon-l-clear"
                Accessible.name: root.stopwatch.running ? qsTr("Pause") : qsTr("Reset")
                onClicked: root.stopwatch.running ? root.stopwatch.stop() : root.stopwatch.reset()
            }
        }
        footer: Item {
            width: list.width
            height: root.topMargin
        }

        delegate: LapTime {
            required property int index
            required property real modelData

            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
            time: modelData
            caption: root.splits.length - index
            color: Theme.secondaryHighlightColor
        }

        VerticalScrollDecorator {}
    }

    component LapTime: Column {
        id: lapTime

        property real time
        property string caption
        property color color

        Label {
            text: Logic.formatStopwatch(lapTime.time)
            font.pixelSize: Theme.fontSizeExtraLarge
            font.features: ({ "tnum": 1 })
            color: lapTime.color
        }
        Label {
            anchors.right: parent.right
            text: lapTime.caption
            font.pixelSize: Theme.fontSizeExtraSmall
            color: lapTime.color
        }
    }
}
