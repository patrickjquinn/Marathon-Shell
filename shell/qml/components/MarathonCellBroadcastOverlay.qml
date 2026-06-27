import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// WEA / ETWS / CMAS emergency alert overlay. Fed by CellBroadcastManagerCpp
// (org.freedesktop.ModemManager1.Modem.CellBroadcast — ModemManager 1.22+).
//
// Visual: red distress banner + large category label + body text. Tone +
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
    visible: CellBroadcastManagerCpp.activeBroadcasts.length > 0
    z: Constants.zIndexModalOverlay + 200 // above modals, below incoming-call

    readonly property var current: visible ? CellBroadcastManagerCpp.activeBroadcasts[0] : null

    function categoryColor(cat) {
        switch (cat) {
        case "presidential":
        case "ETWS":
        case "imminent":
            return MColors.error;
        case "amber":
            return MColors.warning !== undefined ? MColors.warning : "#F59E0B";
        case "test":
            return MColors.textTertiary;
        default:
            return MColors.error;
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
            if (typeof AudioManagerCpp !== "undefined" && AudioManagerCpp.playAlert)
                AudioManagerCpp.playAlert("wea-attention");
        }
        target: CellBroadcastManagerCpp
    }

    // Heavy red background — the WEA spec calls for distinguishable
    // visuals; light theming would underplay the urgency.
    Rectangle {
        anchors.fill: parent
        color: "#0a0000"
        opacity: 0.97
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Constants.safeAreaTop
        height: Math.round(8 * Constants.scaleFactor)
        color: overlay.current ? overlay.categoryColor(overlay.current.category) : MColors.error
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
        width: parent.width - Constants.safeAreaLeft - Constants.safeAreaRight - MSpacing.xl * 2
        spacing: MSpacing.xl

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: "warning"
            size: Math.round(80 * Constants.scaleFactor)
            color: overlay.current ? overlay.categoryColor(overlay.current.category) : MColors.error
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: overlay.current ? overlay.categoryTitle(overlay.current.category) : ""
            color: MColors.textPrimary
            font.pixelSize: MTypography.sizeTitle1
            font.weight: MTypography.weightBold
            font.family: MTypography.fontFamily
            font.letterSpacing: 2
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: overlay.current ? overlay.current.text : ""
            color: MColors.textPrimary
            font.pixelSize: MTypography.sizeTitle3
            font.weight: MTypography.weightMedium
            font.family: MTypography.fontFamily
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
        }

        // Dismiss button — present for normal categories. For
        // Presidential / ETWS the user must long-press the screen for
        // 3 seconds to acknowledge (anti-accidental-dismiss).
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(220 * Constants.scaleFactor)
            height: Math.round(56 * Constants.scaleFactor)
            visible: overlay.current && !overlay.current.nonDismissable

            Rectangle {
                anchors.fill: parent
                radius: MRadius.md
                color: MColors.textPrimary
                opacity: dismissArea.pressed ? 0.85 : 1.0
            }
            Text {
                anchors.centerIn: parent
                text: "Acknowledge"
                color: "#000000"
                font.pixelSize: MTypography.sizeBody
                font.weight: MTypography.weightDemiBold
                font.family: MTypography.fontFamily
            }
            MouseArea {
                id: dismissArea
                anchors.fill: parent
                onClicked: {
                    if (overlay.current)
                        CellBroadcastManagerCpp.acknowledge(overlay.current.path);
                }
            }
        }

        // Non-dismissable categories: long-press hint + 3-second hold gesture.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: Math.round(56 * Constants.scaleFactor)
            visible: overlay.current && overlay.current.nonDismissable

            Text {
                anchors.centerIn: parent
                text: holdTimer.running ? "Hold to acknowledge — " + Math.ceil((3000 - holdTimer.elapsed) / 1000) + " s" : "Touch and hold for 3 seconds to acknowledge"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeFootnote
                font.family: MTypography.fontFamily
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
                        CellBroadcastManagerCpp.acknowledge(overlay.current.path);
                    }
                }
                onRunningChanged: if (!running)
                    elapsed = 0
            }
        }
    }
}
