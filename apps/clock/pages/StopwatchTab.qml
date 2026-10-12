import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

TabItem {
    id: root

    property var app
    readonly property var stopwatch: app.stopwatch

    flickable: list

    SilicaListView {
        id: list

        anchors.fill: parent
        model: root.stopwatch.laps

        header: Column {
            width: list.width
            spacing: Theme.paddingLarge
            topPadding: Theme.paddingLarge * 2
            bottomPadding: Theme.paddingLarge

            Label {
                objectName: "stopwatchTime"
                anchors.horizontalCenter: parent.horizontalCenter
                text: Logic.formatStopwatch(root.stopwatch.elapsed)
                font.pixelSize: Theme.fontSizeHuge
                font.features: ({ "tnum": 1 })
                color: root.stopwatch.running ? Theme.highlightColor : Theme.primaryColor
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge

                Button {
                    objectName: "startStop"
                    text: root.stopwatch.running ? qsTr("Stop") : qsTr("Start")
                    onClicked: root.stopwatch.running ? root.stopwatch.stop() : root.stopwatch.start()
                }
                Button {
                    objectName: "lapReset"
                    text: root.stopwatch.running ? qsTr("Lap") : qsTr("Reset")
                    enabled: root.stopwatch.running || root.stopwatch.elapsed > 0
                    onClicked: root.stopwatch.running ? root.stopwatch.lap() : root.stopwatch.reset()
                }
            }
        }

        delegate: Item {
            id: lap

            required property int index
            required property real modelData

            width: list.width
            height: Theme.itemSizeSmall

            Label {
                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Lap %1").arg(lap.index + 1)
                color: Theme.secondaryColor
            }
            Label {
                anchors.right: parent.right
                anchors.rightMargin: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                text: Logic.formatStopwatch(lap.modelData)
                font.features: ({ "tnum": 1 })
            }
        }

        VerticalScrollDecorator {}
    }
}
