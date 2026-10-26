import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: root

    property alias backCounter: backCounter
    property alias homeCounter: homeCounter
    property int hintDuration: 6000
    property int minVisible: 1500
    property bool homePending: false
    property var pendingCounter: null
    readonly property bool appLike: UIStore.appWindowOpen || UIStore.settingsOpen
    readonly property bool ready: SettingsManagerCpp.firstRunComplete && !SessionStore.isLocked && Display.screenOn
    readonly property string text: backLabel.visible ? backLabel.text : homeLabel.text
    readonly property bool showing: backLabel.visible || homeLabel.visible

    function hide() {
        backLabel.visible = false;
        homeLabel.visible = false;
        pendingCounter = null;
        timeout.stop();
        seen.stop();
    }

    function show(label, counter) {
        if (!counter.active)
            return;
        pendingCounter = counter;
        label.visible = true;
        timeout.restart();
        seen.restart();
    }

    function stateChanged() {
        hide();
        if (!ready)
            return;
        if (appLike) {
            homePending = true;
            show(backLabel, backCounter);
        } else if (homePending) {
            homePending = false;
            show(homeLabel, homeCounter);
        }
    }

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Constants.navBarHeight
    height: childrenRect.height
    opacity: showing ? 1 : 0
    z: Constants.zIndexNavBarApp - 1

    Behavior on opacity {
        NumberAnimation {
            duration: MMotion.reduceMotion ? 0 : 200
        }
    }

    onAppLikeChanged: stateChanged()
    onReadyChanged: {
        if (!ready)
            hide();
    }

    Timer {
        id: seen

        interval: root.minVisible
        onTriggered: {
            if (root.ready && root.pendingCounter)
                root.pendingCounter.exhaust();
        }
    }

    Silica.FirstTimeUseCounter {
        id: backCounter

        key: "/apps/marathon/hints/back"
        limit: 1
        ignoreSystemHints: true
    }

    Silica.FirstTimeUseCounter {
        id: homeCounter

        key: "/apps/marathon/hints/quicksettings"
        limit: 1
        ignoreSystemHints: true
    }

    Timer {
        id: timeout

        interval: root.hintDuration
        onTriggered: root.hide()
    }

    Silica.InteractionHintLabel {
        id: backLabel

        visible: false
        anchors.bottom: parent.bottom
        topMargin: Silica.Theme.paddingLarge
        bottomMargin: Silica.Theme.paddingLarge
        //: One-time hint after the first app opens
        text: qsTr("Drag the bar left to go back")
    }

    Silica.InteractionHintLabel {
        id: homeLabel

        visible: false
        anchors.bottom: parent.bottom
        topMargin: Silica.Theme.paddingLarge
        bottomMargin: Silica.Theme.paddingLarge
        //: One-time hint on the first return to the home screen
        text: qsTr("Pull the bar down for quick settings")
    }
}
