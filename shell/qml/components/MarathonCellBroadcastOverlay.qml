import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// WEA / ETWS / CMAS emergency alert overlay. Fed by Modem
// (org.freedesktop.ModemManager1.Modem.CellBroadcast — ModemManager 1.22+).
//
// Visual: pulsing red strip + category label + body text on the ambience. Tone +
// distinguishable vibration on arrival; non-dismissable categories
// (Presidential WEA, ETWS earthquake/tsunami) suppress the dismiss
// button per FCC §10.500 and MIC ordinance — the user must wait for the
// network to expire the broadcast OR ack it via a long-press.
//
// We layer above the lock screen and PIN entry on purpose: an Amber
// Alert that fires while the screen is locked must still display. The
// only thing that should occlude a Presidential Alert is an active
// 911 voice call. That gating lives in MarathonShell.qml's state
// machine.
Item {
    id: overlay

    anchors.fill: parent
    visible: Modem.activeBroadcasts.length > 0
    z: Constants.zIndexModalOverlay + 200 // above modals, below incoming-call

    readonly property var current: visible ? Modem.activeBroadcasts[0] : null

    function categoryColor(cat) {
        switch (cat) {
        case "presidential":
        case "ETWS":
        case "imminent":
            return Silica.Theme.errorColor;
        case "amber":
            return MColors.warning !== undefined ? MColors.warning : "#F59E0B";
        case "test":
            return Silica.Theme.secondaryColor;
        default:
            return Silica.Theme.errorColor;
        }
    }

    function categoryTitle(cat) {
        switch (cat) {
        case "presidential":
            return "PRESIDENTIAL ALERT";
        case "imminent":
            return "EMERGENCY ALERT";
        case "amber":
            return "AMBER ALERT";
        case "ETWS":
            return "EARTHQUAKE / TSUNAMI";
        case "test":
            return "TEST ALERT";
        default:
            return "PUBLIC SAFETY ALERT";
        }
    }

    // Distinguishable WEA vibration cadence (FCC §10.520): two 2-second
    // vibrations separated by 1 second of silence, no repetition. The
    // pattern is on/off/on/off in milliseconds — HapticManager's
    // vibratePattern handles arbitrary duration sequences directly. The
    // earlier r199 three-tap workaround was unnecessary; pattern API
    // already existed.
    readonly property var weaPattern: [2000, 1000, 2000]

    Connections {
        function onBroadcastReceived(broadcast) {
            if (typeof HapticManager !== "undefined")
                HapticManager.vibratePattern(overlay.weaPattern, 0);
            // AudioManagerCpp has no play method -- it is the mixer
            // (setVolume/setMuted/streams). The guard `&& playAlert` meant
            // that resolved to undefined and the branch was skipped in
            // silence, so a Wireless Emergency Alert made no sound at all.
            // AudioPolicyControllerCpp is what actually plays shell sounds,
            // as IncomingCallOverlay already does for the ringtone.
            AudioPolicyControllerCpp.playAlarmSound();
        }
        target: Modem
    }

    KeelAmbienceBackground {
        anchors.fill: parent
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }

    // An emergency alert is modal: nothing underneath takes a tap.
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.safeAreaTop
        height: Silica.Theme.paddingSmall
        color: overlay.current ? overlay.categoryColor(overlay.current.category) : Silica.Theme.errorColor
        SequentialAnimation on opacity {
            running: overlay.visible
            loops: Animation.Infinite
            NumberAnimation {
                to: 0.4
                duration: 700
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1.0
                duration: 700
                easing.type: Easing.InOutSine
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - Constants.safeAreaLeft - Constants.safeAreaRight - 2 * Silica.Theme.horizontalPageMargin
        spacing: Silica.Theme.paddingLarge

        GlyphIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "warning"
            size: Silica.Theme.iconSizeExtraLarge
            color: overlay.current ? overlay.categoryColor(overlay.current.category) : Silica.Theme.errorColor
        }

        Silica.Label {
            width: parent.width
            text: overlay.current ? overlay.categoryTitle(overlay.current.category) : ""
            color: Silica.Theme.highlightColor
            font.family: Silica.Theme.fontFamilyHeading
            font.pixelSize: Silica.Theme.fontSizeExtraLarge
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        Silica.Label {
            width: parent.width
            text: overlay.current ? overlay.current.text : ""
            color: Silica.Theme.primaryColor
            font.pixelSize: Silica.Theme.fontSizeMedium
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }

        // Dismiss button — present for normal categories. For
        // Presidential / ETWS the user must long-press the screen for
        // 3 seconds to acknowledge (anti-accidental-dismiss).
        Silica.Button {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: overlay.current && !overlay.current.nonDismissable
            text: "Acknowledge"
            onClicked: {
                if (overlay.current)
                    Modem.acknowledge(overlay.current.path);
            }
        }

        // Non-dismissable categories: long-press hint + 3-second hold gesture.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: Silica.Theme.itemSizeMedium
            visible: overlay.current && overlay.current.nonDismissable

            Silica.Label {
                anchors.centerIn: parent
                width: parent.width
                text: holdTimer.running ? "Hold to acknowledge — " + Math.ceil((3000 - holdTimer.elapsed) / 1000) + " s" : "Touch and hold for 3 seconds to acknowledge"
                color: holdTimer.running ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeSmall
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
                anchors.fill: parent
                onPressed: holdTimer.start()
                onReleased: holdTimer.stop()
                onCanceled: holdTimer.stop()
            }

            Timer {
                id: holdTimer
                property int elapsed: 0
                interval: 100
                repeat: true
                onTriggered: {
                    elapsed += interval;
                    if (elapsed >= 3000 && overlay.current) {
                        elapsed = 0;
                        stop();
                        Modem.acknowledge(overlay.current.path);
                    }
                }
                onRunningChanged: if (!running)
                    elapsed = 0
            }
        }
    }
}
