import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: root

    property var app
    property alias tabs: tabs

    TabView {
        id: tabs

        anchors.fill: parent
        sourceProperty: "page"
        header: TabBar {
            model: tabs.model
        }
        // A ListModel, since TabView's delegate reads the page off `model`,
        // which drops values of a plain JS array.
        model: ListModel {
            Component.onCompleted: {
                append({ title: qsTr("Alarms"), page: alarmsTab });
                append({ title: qsTr("World clock"), page: worldClockTab });
                append({ title: qsTr("Stopwatch"), page: stopwatchTab });
                append({ title: qsTr("Timer"), page: timerTab });
            }
        }
    }

    Component {
        id: alarmsTab
        AlarmsTab { app: root.app }
    }
    Component {
        id: worldClockTab
        WorldClockTab { app: root.app }
    }
    Component {
        id: stopwatchTab
        StopwatchTab { app: root.app }
    }
    Component {
        id: timerTab
        TimerTab { app: root.app }
    }
}
