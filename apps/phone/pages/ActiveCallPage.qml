import MarathonApp.Phone
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

    function show(number, name) {
        callNumber = number;
        callName = name || "Unknown";
        callDuration = 0;
        isMuted = false;
        isSpeakerOn = false;
        visible = true;
    }

    function hide() {
        visible = false;
        callDuration = 0;
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
            callDuration++;
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
                text: callName.charAt(0).toUpperCase()
                font.pixelSize: MTypography.sizeXLarge * 2
                font.weight: Font.Bold
                color: MColors.accent
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: callName
            font.pixelSize: MTypography.sizeXLarge
            font.weight: Font.Bold
            color: MColors.text
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: callNumber
            font.pixelSize: MTypography.sizeLarge
            color: MColors.textSecondary
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: formatDuration(callDuration)
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

            Repeater {
                model: [
                    {
                        "icon": isMuted ? "volume-x" : "volume-2",
                        "label": "Mute",
                        "action": "mute"
                    },
                    {
                        "icon": "user-plus",
                        "label": "Add",
                        "action": "add"
                    },
                    {
                        "icon": isSpeakerOn ? "volume-2" : "smartphone",
                        "label": "Speaker",
                        "action": "speaker"
                    },
                    {
                        "icon": "grid",
                        "label": "Keypad",
                        "action": "keypad"
                    },
                    {
                        "icon": "pause",
                        "label": "Hold",
                        "action": "hold"
                    },
                    {
                        "icon": "arrow-left",
                        "label": "Transfer",
                        "action": "transfer"
                    }
                ]

                Column {
                    spacing: MSpacing.sm
                    width: Constants.touchTargetLarge * 1.2

                    Rectangle {
                        id: callActionTile
                        width: Constants.touchTargetLarge
                        height: Constants.touchTargetLarge
                        radius: Constants.borderRadiusSharp
                        color: (modelData.action === "mute" && isMuted) || (modelData.action === "speaker" && isSpeakerOn) ? MColors.accent : MColors.surface
                        border.width: Constants.borderWidthMedium
                        border.color: MColors.border
                        anchors.horizontalCenter: parent.horizontalCenter

                        readonly property bool toggleActive: (modelData.action === "mute" && isMuted) || (modelData.action === "speaker" && isSpeakerOn)

                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.label
                        Accessible.checkable: modelData.action === "mute" || modelData.action === "speaker"
                        Accessible.checked: toggleActive
                        Accessible.onPressAction: callActionMouse.clicked(null)

                        Icon {
                            anchors.centerIn: parent
                            name: modelData.icon === "user-plus" ? "user" : (modelData.icon === "grid" ? "grid" : (modelData.icon === "arrow-left" ? "phone" : modelData.icon))
                            size: Constants.iconSizeLarge
                            color: (modelData.action === "mute" && isMuted) || (modelData.action === "speaker" && isSpeakerOn) ? MColors.text : MColors.textSecondary
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
                                if (modelData.action === "mute") {
                                    isMuted = !isMuted;
                                    TelephonyService.setCallMuted(isMuted);
                                    Logger.info("Phone", "Mute toggled: " + isMuted);
                                } else if (modelData.action === "speaker") {
                                    isSpeakerOn = !isSpeakerOn;
                                    TelephonyService.setSpeakerphone(isSpeakerOn);
                                    Logger.info("Phone", "Speaker toggled: " + isSpeakerOn);
                                } else {
                                    Logger.info("Phone", "Action: " + modelData.action);
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
                        text: modelData.label
                        font.pixelSize: MTypography.sizeSmall
                        color: MColors.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
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
            color: "#E74C3C"
            border.width: Constants.borderWidthThick
            border.color: "#C0392B"

            Accessible.role: Accessible.Button
            Accessible.name: qsTr("End call")
            Accessible.onPressAction: {
                TelephonyService.hangup();
                hide();
            }

            Icon {
                anchors.centerIn: parent
                name: "phone"
                size: Constants.iconSizeLarge
                color: "white"
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
                    hide();
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
