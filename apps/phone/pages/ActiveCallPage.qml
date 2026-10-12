pragma ComponentBehavior: Bound
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: activeCallPage

    property string callNumber: ""
    property string callName: "Unknown"
    property int callDuration: 0
    property bool isMuted: false
    property bool isSpeakerOn: false
    property bool keypadOpen: false
    property string dtmfDigits: ""

    function show(number, name) {
        callNumber = number;
        callName = name || "Unknown";
        callDuration = 0;
        isMuted = false;
        isSpeakerOn = false;
        keypadOpen = false;
        dtmfDigits = "";
        visible = true;
    }

    function hide() {
        visible = false;
        keypadOpen = false;
        callDuration = 0;
    }

    function sendTone(digit) {
        HapticService.light();
        TelephonyService.sendDTMF(digit);
        dtmfDigits += digit;
    }

    function formatDuration(seconds) {
        var hours = Math.floor(seconds / 3600);
        var minutes = Math.floor((seconds % 3600) / 60);
        var secs = seconds % 60;
        if (hours > 0)
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (secs < 10 ? "0" : "") + secs;

        return minutes + ":" + (secs < 10 ? "0" : "") + secs;
    }

    color: MColors.background
    visible: false
    z: 1000

    Timer {
        id: durationTimer

        interval: 1000
        running: activeCallPage.visible
        repeat: true
        onTriggered: {
            activeCallPage.callDuration++;
        }
    }

    // Three anchored regions instead of a centered Column. The old layout
    // used `anchors.centerIn: parent + spacing: MSpacing.xl * 2` with an
    // avatar that was 3× iconSizeXLarge — total column height routinely
    // exceeded the parent surface height, so the avatar got clipped by the
    // status bar at the top AND the end-call button got clipped by the
    // home-indicator at the bottom. Splitting into top / center / bottom
    // anchored regions guarantees nothing escapes the available area no
    // matter what the action-grid size or duration text dimensions do.

    Column {
        id: callerInfo
        anchors.top: parent.top
        anchors.topMargin: MSpacing.xl
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: MSpacing.md
        width: parent.width * 0.8

        Rectangle {
            width: Constants.iconSizeXLarge * 2
            height: Constants.iconSizeXLarge * 2
            radius: width / 2
            color: MColors.surface
            border.width: Constants.borderWidthThick
            border.color: MColors.accent
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                anchors.centerIn: parent
                text: activeCallPage.callName.charAt(0).toUpperCase()
                font.pixelSize: MTypography.sizeXLarge * 2
                font.weight: Font.Bold
                color: MColors.accent
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: activeCallPage.callName
            font.pixelSize: MTypography.sizeXLarge
            font.weight: Font.Bold
            color: MColors.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, parent.width)
            text: activeCallPage.keypadOpen && activeCallPage.dtmfDigits.length > 0 ? activeCallPage.dtmfDigits : activeCallPage.callNumber
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeLarge
            elide: Text.ElideLeft
            color: MColors.textSecondary
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: activeCallPage.formatDuration(activeCallPage.callDuration)
            font.pixelSize: MTypography.sizeBody
            color: MColors.accent
            Accessible.role: Accessible.StaticText
            Accessible.name: qsTr("Call duration %1").arg(text)
        }
    }

    Item {
        id: actionGridRegion
        anchors.top: callerInfo.bottom
        anchors.bottom: endCallContainer.top
        anchors.left: parent.left
        anchors.right: parent.right

        Grid {
            anchors.centerIn: parent
            columns: 3
            spacing: MSpacing.lg
            visible: !activeCallPage.keypadOpen

            Repeater {
                model: [
                    {
                        "icon": activeCallPage.isMuted ? "microphone-slash" : "microphone",
                        "label": qsTr("Mute"),
                        "action": "mute"
                    },
                    {
                        "icon": "dots-nine",
                        "label": qsTr("Keypad"),
                        "action": "keypad"
                    },
                    {
                        "icon": activeCallPage.isSpeakerOn ? "volume-2" : "smartphone",
                        "label": qsTr("Speaker"),
                        "action": "speaker"
                    }
                ]

                Column {
                    id: callAction

                    required property var modelData

                    spacing: MSpacing.sm
                    width: Constants.touchTargetLarge * 1.2

                    Rectangle {
                        readonly property bool toggleActive: (callAction.modelData.action === "mute" && activeCallPage.isMuted) || (callAction.modelData.action === "speaker" && activeCallPage.isSpeakerOn)

                        width: Constants.touchTargetLarge
                        height: Constants.touchTargetLarge
                        radius: Constants.borderRadiusSharp
                        color: toggleActive ? MColors.accent : MColors.surface
                        border.width: Constants.borderWidthMedium
                        border.color: MColors.border
                        anchors.horizontalCenter: parent.horizontalCenter

                        Accessible.role: Accessible.Button
                        Accessible.name: callAction.modelData.label
                        Accessible.checkable: callAction.modelData.action !== "keypad"
                        Accessible.checked: toggleActive
                        Accessible.onPressAction: callActionMouse.clicked(null)

                        Icon {
                            anchors.centerIn: parent
                            name: callAction.modelData.icon
                            size: Constants.iconSizeLarge
                            color: parent.toggleActive ? MColors.text : MColors.textSecondary
                        }

                        MouseArea {
                            id: callActionMouse
                            anchors.fill: parent
                            onPressed: {
                                parent.scale = 0.9;
                                HapticService.light();
                            }
                            onReleased: {
                                parent.scale = 1;
                            }
                            onCanceled: {
                                parent.scale = 1;
                            }
                            onClicked: {
                                if (callAction.modelData.action === "mute") {
                                    activeCallPage.isMuted = !activeCallPage.isMuted;
                                    TelephonyService.setCallMuted(activeCallPage.isMuted);
                                } else if (callAction.modelData.action === "speaker") {
                                    activeCallPage.isSpeakerOn = !activeCallPage.isSpeakerOn;
                                    TelephonyService.setSpeakerphone(activeCallPage.isSpeakerOn);
                                } else {
                                    activeCallPage.keypadOpen = true;
                                }
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                            }
                        }
                    }

                    Text {
                        text: callAction.modelData.label
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: MSpacing.md
            visible: activeCallPage.keypadOpen

            Grid {
                id: dtmfGrid

                readonly property real cellSize: Math.max(MSpacing.touchTargetMin, Math.min((actionGridRegion.width * 0.8 - columnSpacing * 2) / 3, (actionGridRegion.height - hideKeypadButton.height - MSpacing.md - MSpacing.lg * 2 - rowSpacing * 3) / 4, Constants.touchTargetLarge * 1.4))

                anchors.horizontalCenter: parent.horizontalCenter
                columns: 3
                rowSpacing: MSpacing.sm
                columnSpacing: MSpacing.lg

                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]

                    Rectangle {
                        required property string modelData

                        width: dtmfGrid.cellSize
                        height: dtmfGrid.cellSize
                        radius: width / 2
                        color: dtmfArea.pressed ? MColors.bb10Card : MColors.elev2
                        border.width: 1
                        border.color: MColors.whiteOverlay08

                        Accessible.role: Accessible.Button
                        Accessible.name: modelData
                        Accessible.onPressAction: activeCallPage.sendTone(modelData)

                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: Math.round(dtmfGrid.cellSize * 0.36)
                            font.weight: MTypography.weightLight
                        }

                        MouseArea {
                            id: dtmfArea
                            anchors.fill: parent
                            onClicked: activeCallPage.sendTone(parent.modelData)
                        }
                    }
                }
            }

            MButton {
                id: hideKeypadButton

                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Hide keypad")
                variant: "secondary"
                onClicked: activeCallPage.keypadOpen = false
            }
        }
    }

    Item {
        id: endCallContainer
        anchors.bottom: parent.bottom
        anchors.bottomMargin: MSpacing.xl + MSpacing.md
        anchors.horizontalCenter: parent.horizontalCenter
        width: Constants.touchTargetLarge * 1.5
        height: Constants.touchTargetLarge * 1.5

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: MColors.error
            border.width: Constants.borderWidthThick
            border.color: MColors.errorDim

            Accessible.role: Accessible.Button
            Accessible.name: qsTr("End call")
            Accessible.onPressAction: {
                TelephonyService.hangup();
                activeCallPage.hide();
            }

            Icon {
                anchors.centerIn: parent
                name: "phone"
                size: Constants.iconSizeLarge
                color: MColors.textPrimary
                rotation: 135
            }

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    parent.scale = 0.9;
                    HapticService.medium();
                }
                onReleased: {
                    parent.scale = 1;
                }
                onCanceled: {
                    parent.scale = 1;
                }
                onClicked: {
                    TelephonyService.hangup();
                    activeCallPage.hide();
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 100
                }
            }
        }
    }
}
