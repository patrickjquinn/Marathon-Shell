import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import "../components"

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

            // Format date for 3 o'clock position
            dayOfMonth = now.getDate().toString();
            var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
            dayOfWeek = days[now.getDay()];
        }
    }

    Rectangle {
        anchors.fill: parent
        color: MColors.background

        // Main analog clock - centered and large, accounting for alarm bar
        Item {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.7, parent.height * 0.55)
            height: width
            // Account for alarm bar when centering
            anchors.verticalCenterOffset: (clockApp.alarms && clockApp.alarms.length > 0) ? -Constants.actionBarHeight / 2 : 0

            // Squircle clock face with neumorphic design - raised from background
            Item {
                id: clockFaceContainer
                anchors.centerIn: parent
                width: parent.width * 1.10
                height: parent.height * 1.10

                // Dark shadow layer (bottom-right) - disabled (requires Qt 6.5+ MultiEffect)
                // Rectangle {
                //     anchors.fill: parent
                //     anchors.margins: -20
                //     radius: width * 0.22
                //     color: "transparent"
                //
                //     layer.enabled: false
                // }

                // Light shadow layer (top-left) - disabled (requires Qt 6.5+ MultiEffect)
                // Rectangle {
                //     anchors.fill: parent
                //     anchors.margins: -20
                //     radius: width * 0.22
                //     color: "transparent"
                //
                //     layer.enabled: false
                // }

                // Main clock face
                Rectangle {
                    id: clockFace
                    anchors.fill: parent
                    color: MColors.surface
                    radius: width * 0.22

                    // Subtle inner border for definition
                    border.width: Constants.borderWidthThin
                    border.color: Qt.rgba(0, 0, 0, 0.05)
                }

                // Scale factor to keep clock content same size inside larger frame
                property real contentScale: 1.0 / 1.10

                // Container to scale clock content to original size inside the face
                Item {
                    parent: clockFaceContainer
                    anchors.centerIn: parent
                    width: clockFaceContainer.width * clockFaceContainer.contentScale
                    height: clockFaceContainer.height * clockFaceContainer.contentScale

                    // Hour markers (all 60 ticks, with emphasis on hours)
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

                    // Number: 12
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: MSpacing.xl
                        text: "12"
                        font.pixelSize: MTypography.sizeXXLarge
                        font.weight: Font.Bold
                        color: MColors.marathonTeal
                    }

                    // Number: 3 with date
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

                    // Number: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: MSpacing.xl
                        text: "6"
                        font.pixelSize: MTypography.sizeXXLarge
                        font.weight: Font.Bold
                        color: MColors.marathonTeal
                    }

                    // Number: 9
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: MSpacing.xl
                        anchors.verticalCenter: parent.verticalCenter
                        text: "9"
                        font.pixelSize: MTypography.sizeXXLarge
                        font.weight: Font.Bold
                        color: MColors.marathonTeal
                    }

                    // PM indicator
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: MSpacing.xl * 1.5
                        text: hours >= 12 ? "PM" : "AM"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.Normal
                        color: MColors.marathonTeal
                    }

                    // Hour hand - darker gray with inner baton stripe (40% from center)
                    Item {
                        id: hourHand
                        width: parent.width
                        height: parent.height
                        rotation: (hours % 12) * 30 + minutes * 0.5

                        Behavior on rotation {
                            RotationAnimation {
                                duration: Constants.animationSlow
                                direction: RotationAnimation.Shortest
                            }
                        }

                        property real handLength: parent.height * 0.25

                        // Outer hand
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThick + 4
                            height: hourHand.handLength
                            color: "#4A4A4A"  // Darker gray
                            radius: width / 2
                        }

                        // Inner baton (lighter stripe - only 40% from center)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -(hourHand.handLength * 0.4) / 2
                            width: Constants.borderWidthThin
                            height: hourHand.handLength * 0.4
                            color: "#707070"  // Lighter gray baton
                        }
                    }

                    // Minute hand - even darker gray with inner baton (FULL LENGTH)
                    Item {
                        id: minuteHand
                        width: parent.width
                        height: parent.height
                        rotation: minutes * 6 + seconds * 0.1

                        Behavior on rotation {
                            RotationAnimation {
                                duration: Constants.animationSlow
                                direction: RotationAnimation.Shortest
                            }
                        }

                        property real handLength: parent.height * 0.38

                        // Outer hand
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThick + 2
                            height: minuteHand.handLength
                            color: "#2A2A2A"  // Even darker gray
                            radius: width / 2
                        }

                        // Inner baton (lighter stripe - FULL LENGTH to tip)
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThin
                            height: minuteHand.handLength
                            color: "#505050"  // Lighter gray baton
                        }
                    }

                    // Second hand - teal accent, thin
                    Item {
                        id: secondHand
                        width: parent.width
                        height: parent.height
                        rotation: seconds * 6

                        Behavior on rotation {
                            RotationAnimation {
                                duration: Constants.animationFast
                                direction: RotationAnimation.Shortest
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -height / 2
                            width: Constants.borderWidthThin
                            height: parent.height * 0.42
                            color: MColors.marathonTeal
                        }
                    }

                    // Center pivot point - circular
                    Rectangle {
                        anchors.centerIn: parent
                        width: MSpacing.md
                        height: MSpacing.md
                        radius: width / 2
                        color: "#404040"  // Dark gray
                        border.width: 1
                        border.color: "#606060"
                        z: 10
                    }
                }  // End of scaled content container
            }
        }

        // Bottom alarm info bar (if alarms exist)
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

            // Alarm toggle
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
