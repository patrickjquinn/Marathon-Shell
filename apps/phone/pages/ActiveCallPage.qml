import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: activeCallPage
    color: MColors.background
    visible: false
    z: 1000

    property string callNumber: ""
    property string callName: "Unknown"
    property int callDuration: 0
    property bool isMuted: false
    property bool isSpeakerOn: false

    Timer {
        id: durationTimer
        interval: 1000
        running: activeCallPage.visible
        repeat: true
        onTriggered: {
            callDuration++;
        }
    }

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

        if (hours > 0) {
            return hours + ":" + (minutes < 10 ? "0" : "") + minutes + ":" + (secs < 10 ? "0" : "") + secs;
        }
        return minutes + ":" + (secs < 10 ? "0" : "") + secs;
    }

    Column {
        anchors.centerIn: parent
        spacing: MSpacing.xl * 2
        width: parent.width * 0.8

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: MSpacing.lg

            Rectangle {
                width: Constants.iconSizeXLarge * 3
                height: Constants.iconSizeXLarge * 3
                radius: width / 2
                color: MColors.surface
                border.width: Constants.borderWidthThick
                border.color: MColors.accent
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    anchors.centerIn: parent
                    text: callName.charAt(0).toUpperCase()
                    font.pixelSize: MTypography.sizeXLarge * 3
                    font.weight: Font.Bold
                    color: MColors.accent
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: MSpacing.sm

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: callName
                    font.pixelSize: MTypography.sizeXLarge
                    font.weight: Font.Bold
                    color: MColors.text
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: callNumber
                    font.pixelSize: MTypography.sizeLarge
                    color: MColors.textSecondary
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: formatDuration(callDuration)
                    font.pixelSize: MTypography.sizeBody
                    color: MColors.accent
                }
            }
        }

        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            spacing: MSpacing.lg

            Repeater {
                model: [
                    {
                        icon: isMuted ? "volume-x" : "volume-2",
                        label: "Mute",
                        action: "mute"
                    },
                    {
                        icon: "user-plus",
                        label: "Add",
                        action: "add"
                    },
                    {
                        icon: isSpeakerOn ? "volume-2" : "smartphone",
                        label: "Speaker",
                        action: "speaker"
                    },
                    {
                        icon: "grid",
                        label: "Keypad",
                        action: "keypad"
                    },
                    {
                        icon: "pause",
                        label: "Hold",
                        action: "hold"
                    },
                    {
                        icon: "arrow-left",
                        label: "Transfer",
                        action: "transfer"
                    }
                ]

                Column {
                    spacing: MSpacing.sm
                    width: Constants.touchTargetLarge * 1.2

                    Rectangle {
                        width: Constants.touchTargetLarge
                        height: Constants.touchTargetLarge
                        radius: Constants.borderRadiusSharp
                        color: (modelData.action === "mute" && isMuted) || (modelData.action === "speaker" && isSpeakerOn) ? MColors.accent : MColors.surface
                        border.width: Constants.borderWidthMedium
                        border.color: MColors.border
                        anchors.horizontalCenter: parent.horizontalCenter

                        Icon {
                            anchors.centerIn: parent
                            name: modelData.icon === "user-plus" ? "user" : (modelData.icon === "grid" ? "grid" : (modelData.icon === "arrow-left" ? "phone" : modelData.icon))
                            size: Constants.iconSizeLarge
                            color: (modelData.action === "mute" && isMuted) || (modelData.action === "speaker" && isSpeakerOn) ? MColors.text : MColors.textSecondary
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                parent.scale = 0.9;
                                HapticService.light();
                            }
                            onReleased: {
                                parent.scale = 1.0;
                            }
                            onCanceled: {
                                parent.scale = 1.0;
                            }
                            onClicked: {
                                if (modelData.action === "mute") {
                                    isMuted = !isMuted;
                                    if (typeof AudioRoutingManagerCpp !== 'undefined') {
                                        AudioRoutingManagerCpp.setMuted(isMuted);
                                    }
                                    Logger.info("Phone", "Mute toggled: " + isMuted);
                                } else if (modelData.action === "speaker") {
                                    isSpeakerOn = !isSpeakerOn;
                                    if (typeof AudioRoutingManagerCpp !== 'undefined') {
                                        AudioRoutingManagerCpp.setSpeakerphone(isSpeakerOn);
                                    }
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

        Rectangle {
            width: Constants.touchTargetLarge * 1.5
            height: Constants.touchTargetLarge * 1.5
            radius: width / 2
            color: "#E74C3C"
            border.width: Constants.borderWidthThick
            border.color: "#C0392B"
            anchors.horizontalCenter: parent.horizontalCenter

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
                    parent.scale = 1.0;
                }
                onCanceled: {
                    parent.scale = 1.0;
                }
                onClicked: {
                    if (typeof TelephonyService !== 'undefined') {
                        TelephonyService.hangup();
                    }
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
