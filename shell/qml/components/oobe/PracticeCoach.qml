pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Item {
    id: root

    property bool running: false
    property int failedTries: 0
    property int idleTimeout: 8000
    property int maxFailedTries: 2
    property int direction: Silica.TouchInteraction.Right
    property int interactionMode: Silica.TouchInteraction.EdgeSwipe
    property bool demoStarted: false
    property bool demoDone: false
    readonly property bool showDemo: running && demoStarted
    readonly property bool showNotNow: running && demoDone

    signal notNow

    function reset() {
        demoStarted = false;
        demoDone = false;
        hint.stop();
        if (running)
            idle.restart();
        else
            idle.stop();
    }

    onRunningChanged: reset()
    onFailedTriesChanged: {
        if (!running || demoStarted)
            return;
        if (failedTries >= maxFailedTries)
            demoStarted = true;
        else
            idle.restart();
    }
    onDemoStartedChanged: {
        if (demoStarted) {
            idle.stop();
            hint.start();
        }
    }

    Timer {
        id: idle

        interval: root.idleTimeout
        onTriggered: root.demoStarted = true
    }

    Silica.TouchInteractionHint {
        id: hint

        objectName: "practiceDemo"
        direction: root.direction
        interactionMode: root.interactionMode
        loops: MMotion.reduceMotion ? 1 : 3
        onRunningChanged: {
            if (!running && root.demoStarted)
                Qt.callLater(() => {
                    if (!hint.running && root.demoStarted)
                        root.demoDone = true;
                });
        }
    }

    Silica.SecondaryButton {
        objectName: "practiceNotNow"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Silica.Theme.paddingLarge
        visible: root.showNotNow
        //: Dismisses the practice and moves on
        text: qsTr("Not now")
        onClicked: root.notNow()
    }
}
