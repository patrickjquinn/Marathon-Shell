import MarathonApp.Clock
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

// Marathon DS · Clock (screens-apps-2.jsx:ClockApp).
//
// MTopBar "Clock" + small "+" + ellipsis. Bare analog dial on black
// (no bay) — 60 tick marks, longer hour ticks, numerals at 12/3/6/9,
// FRI day-of-week left-of-center, AM/PM below center. White hour +
// minute hands; teal-bright second hand with center pivot.
// Below the dial: WORLD CLOCKS card (Local + a few +offset cities).
Item {
    id: clockPage

    property int hours: 0
    property int minutes: 0
    property int seconds: 0
    property string dayOfWeek: ""
    // Wall-clock right-now value; world-clock rows derive their times from
    // this by formatting in each city's IANA timezone via Intl.DateTimeFormat
    // (handles DST and historical offsets correctly — hardcoded "+5h" /
    // "+14h" string offsets do not).
    property var nowDate: new Date()

    function fmt12(h) {
        const h12 = h % 12;
        return (h12 === 0 ? 12 : h12).toString();
    }
    function pad2(n) {
        return n < 10 ? "0" + n : n.toString();
    }

    // Returns { time: "7:08 AM", weekday: "FRI", offsetLabel: "+5h" }
    // for a given IANA timezone relative to the current wall clock.
    //
    // Delegates to the C++ WorldClockHelper context property provided by
    // marathon-app-runner. The QML JS engine in Qt 6.x silently drops the
    // `timeZone` option on Date.toLocaleString, so a pure-JS path here
    // would show the same local time on every row. QTimeZone in C++ has
    // a full DST-correct IANA database.
    property var _nowTick: nowDate  // re-trigger timeIn() each tick
    function timeIn(tz) {
        // Touch the tick property so QML re-evaluates this binding once
        // a second; the result is then used by the world-clocks Repeater.
        const _ = _nowTick;
        if (typeof WorldClockHelper === "undefined")
            return {
                time: "—:—",
                weekday: "",
                offsetLabel: tz
            };
        return WorldClockHelper.timeIn(tz);
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date();
            clockPage.nowDate = now;
            clockPage.hours = now.getHours();
            clockPage.minutes = now.getMinutes();
            clockPage.seconds = now.getSeconds();
            const days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];
            clockPage.dayOfWeek = days[now.getDay()];
        }
    }

    // ── Header ───────────────────────────────────────────────
    MTopBar {
        id: topBar
        width: parent.width
        title: "Clock"
        anchors.top: parent.top
        actions: [
            Icon {
                name: "plus"
                size: 22
                color: MColors.textSecondary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: HapticService.light()
                }
            },
            Icon {
                name: "ellipsis-vertical"
                size: 22
                color: MColors.textSecondary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: HapticService.light()
                }
            }
        ]
    }

    // ── Analog dial ─────────────────────────────────────────
    Item {
        id: dialFrame
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 18
        height: width

        readonly property real dialSize: Math.min(parent.width * 0.78, height - 36)

        Item {
            id: dial
            anchors.centerIn: parent
            width: dialFrame.dialSize
            height: width

            // Tick marks — 60 thin teal-bright strokes; hour ticks at
            // every 5th are thicker and slightly longer.
            Repeater {
                model: 60

                Item {
                    width: dial.width
                    height: dial.height
                    rotation: index * 6

                    Rectangle {
                        property bool isHourMarker: index % 5 === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        width: isHourMarker ? 2 : 1
                        height: isHourMarker ? 12 : 6
                        color: MColors.marathonTealBright
                        opacity: isHourMarker ? 0.9 : 0.55
                    }
                }
            }

            // Hour numerals — 12 / 3 / 6 / 9 only per JSX.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 26
                text: "12"
                color: MColors.marathonTealBright
                font.family: MTypography.fontFamily
                font.pixelSize: 22
                font.weight: Font.Medium
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "3"
                color: MColors.marathonTealBright
                font.family: MTypography.fontFamily
                font.pixelSize: 22
                font.weight: Font.Medium
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 26
                text: "6"
                color: MColors.marathonTealBright
                font.family: MTypography.fontFamily
                font.pixelSize: 22
                font.weight: Font.Medium
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "9"
                color: MColors.marathonTealBright
                font.family: MTypography.fontFamily
                font.pixelSize: 22
                font.weight: Font.Medium
            }

            // Day-of-week label, left of center.
            Text {
                anchors.right: parent.horizontalCenter
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: clockPage.dayOfWeek
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: Font.Medium
                font.letterSpacing: 1
            }

            // AM/PM label, below center.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 26
                text: clockPage.hours >= 12 ? "PM" : "AM"
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: Font.Medium
                font.letterSpacing: 1
            }

            // Hour hand — white, thick.
            Item {
                id: hourHand
                anchors.fill: parent
                rotation: (clockPage.hours % 12) * 30 + clockPage.minutes * 0.5

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -(parent.height * 0.21) / 2
                    width: 3
                    height: parent.height * 0.24
                    radius: 1.5
                    color: MColors.textPrimary
                }

                Behavior on rotation {
                    RotationAnimation {
                        duration: Constants.animationSlow
                        direction: RotationAnimation.Shortest
                    }
                }
            }

            // Minute hand — white, thinner, longer.
            Item {
                id: minuteHand
                anchors.fill: parent
                rotation: clockPage.minutes * 6 + clockPage.seconds * 0.1

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -(parent.height * 0.36) / 2
                    width: 2
                    height: parent.height * 0.40
                    radius: 1
                    color: MColors.textPrimary
                }

                Behavior on rotation {
                    RotationAnimation {
                        duration: Constants.animationSlow
                        direction: RotationAnimation.Shortest
                    }
                }
            }

            // Second hand — teal-bright, full length, thin.
            Item {
                id: secondHand
                anchors.fill: parent
                rotation: clockPage.seconds * 6

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -(parent.height * 0.40) / 2
                    width: 1
                    height: parent.height * 0.44
                    color: MColors.marathonTealBright
                }
            }

            // Center pivot — small teal disc.
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: MColors.marathonTealBright
                z: 5

                Rectangle {
                    anchors.centerIn: parent
                    width: 3
                    height: 3
                    radius: 1.5
                    color: "#000000"
                }
            }
        }
    }

    // ── WORLD CLOCKS card ───────────────────────────────────
    Item {
        anchors.top: dialFrame.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 14

        Text {
            id: worldEyebrow
            anchors.left: parent.left
            anchors.leftMargin: 20
            text: "WORLD CLOCKS"
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeEyebrow
            font.weight: Font.Bold
            font.letterSpacing: MTypography.trackingEyebrow
        }

        Rectangle {
            id: worldCard
            anchors.top: worldEyebrow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 10
            height: 4 * 60
            radius: MRadius.md
            color: MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay04

            Column {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    // City list with IANA tz identifiers. Offset + weekday
                    // are computed live from clockPage.nowDate via
                    // Intl.DateTimeFormat — DST-correct, no string math.
                    model: [
                        {
                            city: "New York",
                            tz: "America/New_York"
                        },
                        {
                            city: "London",
                            tz: "Europe/London"
                        },
                        {
                            city: "Tokyo",
                            tz: "Asia/Tokyo"
                        },
                        {
                            city: "Sydney",
                            tz: "Australia/Sydney"
                        }
                    ]
                    delegate: Item {
                        width: worldCard.width
                        height: 60

                        readonly property var resolved: clockPage.timeIn(modelData.tz)

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                text: resolved.offsetLabel
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.weight: Font.Regular
                            }
                            Text {
                                text: modelData.city
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Medium
                            }
                        }

                        Column {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            Text {
                                anchors.right: parent.right
                                text: resolved.time
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: 20
                                font.weight: Font.Light
                                font.features: ({
                                        "tnum": 1
                                    })
                            }
                            Text {
                                anchors.right: parent.right
                                text: resolved.weekday
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.features: ({
                                        "tnum": 1
                                    })
                            }
                        }

                        Rectangle {
                            visible: index < 3
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            height: 1
                            color: MColors.whiteOverlay04
                        }
                    }
                }
            }
        }
    }
}
