import MarathonApp.Clock
import MarathonOS.Shell
import MarathonUI.Theme
import QtQuick

Item {
    id: clockPage

    property int hours: 0
    property int minutes: 0
    property int seconds: 0
    property string currentDate: ""
    property string dayOfMonth: ""
    property string dayOfWeek: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date();
            hours = now.getHours();
            minutes = now.getMinutes();
            seconds = now.getSeconds();
            dayOfMonth = now.getDate().toString();
            var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
            dayOfWeek = days[now.getDay()];
        }
    }

    Rectangle {
        anchors.fill: parent
        color: MColors.background

        Item {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.7, parent.height * 0.55)
            height: width
            anchors.verticalCenterOffset: (clockApp.alarms && clockApp.alarms.length > 0) ? -Constants.actionBarHeight / 2 : 0

            Item {
                id: clockFaceContainer

                property real contentScale: 1 / 1.1

                anchors.centerIn: parent
                width: parent.width * 1.1
                height: parent.height * 1.1

                Rectangle {
                    id: clockFace

                    anchors.fill: parent
                    color: MColors.surface
                    radius: width * 0.22
                    border.width: Constants.borderWidthThin
                    border.color: Qt.rgba(0, 0, 0, 0.05)
                }

                Item {
                    parent: clockFaceContainer
                    anchors.centerIn: parent
                    width: clockFaceContainer.width * clockFaceContainer.contentScale
                    height: clockFaceContainer.height * clockFaceContainer.contentScale

                    Repeater {
                        model: 60

                        Item {
                            width: parent.width
                            height: parent.height
                            rotation: index * 6

                            Rectangle {
                                property bool isHourMarker: index % 5 === 0

                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: MSpacing.md
                                width: isHourMarker ? Constants.borderWidthThick : Constants.borderWidthThin
                                height: isHourMarker ? MSpacing.md : MSpacing.sm
                                color: MColors.marathonTeal
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: MSpacing.xl
                        text: "12"
                        font.pixelSize: MTypography.sizeXXLarge
                        font.weight: Font.Bold
                        color: MColors.marathonTeal
                    }

                    Column {
                        anchors.right: parent.right
                        anchors.rightMargin: MSpacing.xl
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: MSpacing.xs

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayOfMonth
                            font.pixelSize: MTypography.sizeBody
                            font.weight: Font.Normal
                            color: MColors.marathonTeal
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayOfWeek
                            font.pixelSize: MTypography.sizeSmall
                            font.weight: Font.Normal
                            color: MColors.marathonTeal
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "3"
                            font.pixelSize: MTypography.sizeXXLarge
                            font.weight: Font.Bold
                            color: MColors.marathonTeal
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: MSpacing.xl
                        text: "6"
                        font.pixelSize: MTypography.sizeXXLarge
                        font.weight: Font.Bold
                        color: MColors.marathonTeal
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: MSpacing.xl
                        anchors.verticalCenter: parent.verticalCenter
                        text: "9"
                        font.pixelSize: MTypography.sizeXXLarge
                        font.weight: Font.Bold
                        color: MColors.marathonTeal
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: MSpacing.xl * 1.5
                        text: hours >= 12 ? "PM" : "AM"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.Normal
                        color: MColors.marathonTeal
                    }

                    Item {
                        id: hourHand

                        property real handLength: parent.height * 0.25

                        width: parent.width
                        height: parent.height
                        rotation: (hours % 12) * 30 + minutes * 0.5

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThick + 4
                            height: hourHand.handLength
                            color: "#4A4A4A"
                            radius: width / 2
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -(hourHand.handLength * 0.4) / 2
                            width: Constants.borderWidthThin
                            height: hourHand.handLength * 0.4
                            color: "#707070"
                        }

                        Behavior on rotation {
                            RotationAnimation {
                                duration: Constants.animationSlow
                                direction: RotationAnimation.Shortest
                            }
                        }
                    }

                    Item {
                        id: minuteHand

                        property real handLength: parent.height * 0.38

                        width: parent.width
                        height: parent.height
                        rotation: minutes * 6 + seconds * 0.1

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThick + 2
                            height: minuteHand.handLength
                            color: "#2A2A2A"
                            radius: width / 2
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThin
                            height: minuteHand.handLength
                            color: "#505050"
                        }

                        Behavior on rotation {
                            RotationAnimation {
                                duration: Constants.animationSlow
                                direction: RotationAnimation.Shortest
                            }
                        }
                    }

                    Item {
                        id: secondHand

                        width: parent.width
                        height: parent.height
                        rotation: seconds * 6

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThin
                            height: parent.height * 0.42
                            color: MColors.marathonTeal
                        }

                        Behavior on rotation {
                            RotationAnimation {
                                duration: Constants.animationFast
                                direction: RotationAnimation.Shortest
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: MSpacing.md
                        height: MSpacing.md
                        radius: width / 2
                        color: "#404040"
                        border.width: 1
                        border.color: "#606060"
                        z: 10
                    }
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Constants.actionBarHeight
            color: MColors.background
            visible: clockApp.alarms && clockApp.alarms.length > 0

            Column {
                anchors.left: parent.left
                anchors.leftMargin: MSpacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: MSpacing.xs

                Row {
                    spacing: MSpacing.sm

                    Text {
                        text: {
                            if (!clockApp.alarms || clockApp.alarms.length === 0)
                                return "";

                            var alarm = clockApp.alarms[0];
                            var h = (alarm.hour !== undefined ? alarm.hour : 0) % 12;
                            if (h === 0)
                                h = 12;

                            var m = alarm.minute !== undefined ? alarm.minute : 0;
                            var mStr = m < 10 ? "0" + m : m.toString();
                            return h + ":" + mStr;
                        }
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Normal
                        color: MColors.textPrimary
                    }

                    Text {
                        text: (clockApp.alarms && clockApp.alarms.length > 0 && clockApp.alarms[0].label) ? clockApp.alarms[0].label : "Alarm Off"
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Normal
                        color: MColors.textPrimary
                    }
                }

                Text {
                    text: "No Recurrence"
                    font.pixelSize: MTypography.sizeSmall
                    color: MColors.marathonTeal
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: MSpacing.lg
                anchors.verticalCenter: parent.verticalCenter
                width: Constants.touchTargetMedium
                height: Constants.touchTargetMedium
                radius: width / 2
                color: MColors.surface

                ClockIcon {
                    anchors.centerIn: parent
                    name: "bell"
                    size: Constants.iconSizeMedium
                    color: MColors.textSecondary
                }
            }
        }
    }
}
