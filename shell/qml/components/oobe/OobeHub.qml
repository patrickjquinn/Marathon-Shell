pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import ".."

Item {
    id: root

    property bool succeeded: false
    property int failedTries: 0
    property real pullPeak: 0

    signal done

    function handleBack(): bool {
        return false;
    }

    function enter() {
        succeeded = false;
        failedTries = 0;
        pullPeak = 0;
        peek.closePeek();
        // A flag rather than a store lookup: it holds across a setup restart.
        if (String(SettingsManagerCpp.get("onboarding/welcomePosted", false)) !== "true") {
            SettingsManagerCpp.set("onboarding/welcomePosted", true);
            NotificationService.addNotification("Marathon", qsTr("Welcome to Marathon"), qsTr("Swipe in from the left edge any time to see what's new."), "bell");
        }
    }

    function succeed() {
        if (succeeded)
            return;
        succeeded = true;
        finish.restart();
    }

    onVisibleChanged: {
        if (visible)
            enter();
    }

    Column {
        id: copy

        anchors.top: parent.top
        anchors.topMargin: Silica.Theme.paddingLarge
        x: Silica.Theme.horizontalPageMargin
        width: parent.width - 2 * x
        spacing: Silica.Theme.paddingMedium

        Silica.Label {
            objectName: "oobeHubHeading"
            width: parent.width
            text: root.succeeded ? qsTr("That's it") : qsTr("Your Hub")
            wrapMode: Text.Wrap
            color: Silica.Theme.highlightColor
            font.pixelSize: Silica.Theme.fontSizeLarge
        }

        Silica.Label {
            objectName: "oobeHubLead"
            width: parent.width
            text: root.succeeded ? qsTr("Let go part-way to glance; keep going to open it.") : qsTr("Messages and notifications wait at the left edge. Swipe in to peek.")
            wrapMode: Text.Wrap
            color: Silica.Theme.secondaryColor
            font.pixelSize: Silica.Theme.fontSizeSmall
        }
    }

    MarathonPeek {
        id: peek

        objectName: "oobeHubPeek"
        anchors.fill: parent
        onIconsShownChanged: if (iconsShown)
            root.succeed()
        onIsFullyOpenChanged: if (isFullyOpen)
            root.succeed()
        onPeekProgressChanged: {
            if (isPeeking)
                root.pullPeak = Math.max(root.pullPeak, peekProgress);
        }
        onIsPeekingChanged: {
            if (isPeeking)
                root.pullPeak = 0;
        }
        onClosed: {
            // A drag that left the edge and fell short; a bare tap does not count.
            if (!root.succeeded && root.pullPeak > 0)
                ++root.failedTries;
            root.pullPeak = 0;
        }
    }

    PracticeCoach {
        anchors.fill: parent
        running: root.visible && !root.succeeded
        failedTries: root.failedTries
        onNotNow: root.done()
    }

    Timer {
        id: finish

        interval: 1500
        onTriggered: root.done()
    }
}
