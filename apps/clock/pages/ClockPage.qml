import MarathonOS.Shell
import MarathonUI.Containers
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
    }

    // ── Analog dial ─────────────────────────────────────────
    // The dial is laid out inside a frame sized to the dial itself
    // (plus a small breathing margin) rather than a full-width
    // square. Reserving width × width pushed the World Clocks card
    // off the bottom of the content area on 540 × 1140; matching
    // dialFrame.height to dialSize keeps the layout vertically
    // honest and leaves the card a clear ~80 px of headroom above
    // the tab bar.
    Item {
        id: dialFrame
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 18
        height: dialSize + 24

        readonly property real dialSize: Math.round(parent.width * 0.60)

        Item {
            id: dial
            anchors.centerIn: parent
            width: dialFrame.dialSize
            height: width

            // Outer ring — thin teal-bright circle sitting just inside
            // the tick markers, per the JSX ref-clock outline. Mirrors
            // the dial's outer edge so the ticks read as ring-mounted
            // strokes rather than free-floating lines.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: MColors.marathonTealBright
                opacity: 0.45
            }

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

            // Hour numerals — 12 / 3 / 6 / 9 only per JSX. Numeral inset
            // = tick-edge inset (10) + tick-length (12) + breathing room
            // (~16) so glyphs sit clearly inside the tick ring instead of
            // grazing the inner end of the hour ticks.
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 38
                text: "12"
                color: MColors.marathonTealBright
                font.family: MTypography.fontFamily
                font.pixelSize: 22
                font.weight: Font.Medium
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 38
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
                anchors.bottomMargin: 38
                text: "6"
                color: MColors.marathonTealBright
                font.family: MTypography.fontFamily
                font.pixelSize: 22
                font.weight: Font.Medium
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 38
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
    //
    // Lays out the card with the same gutters the rest of Marathon
    // uses: 16 px outer page padding, an eyebrow aligned to the card
    // edge (not extra-indented), and an MCard so the surface picks
    // up the DS elev-3 / top-only highlight treatment instead of
    // a flat elev-2 rectangle. Row height is 72 px with full-bleed
    // dividers; previously rows were 60 px and labels crowded the
    // teal-bright clock readout on the right.
    Item {
        id: worldSection
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        // 12 px above the bottom edge keeps the card visually decoupled
        // from the underlying tab bar (which renders its own 1 px hairline
        // divider). Anchored to parent.bottom rather than dialFrame.bottom
        // so on smaller canvases the dial absorbs the squeeze instead of
        // the card overflowing past the tab bar.
        anchors.bottomMargin: 12
        height: worldEyebrow.height + 12 + worldCard.height

        Text {
            id: worldEyebrow
            anchors.left: parent.left
            text: "WORLD CLOCKS"
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeEyebrow
            font.weight: Font.Bold
            font.letterSpacing: MTypography.trackingEyebrow
        }

        MCard {
            id: worldCard
            anchors.top: worldEyebrow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 12
            elevation: 3
            // Row delegates below are 72 px tall; size the card to match
            // (4 cities × 72) + 16 px breathing room. The previous 4 × 64
            // shortfall caused Sydney to extend past the card and bleed
            // through the bottom tab bar's 78%-opaque glass background.
            height: 4 * 72 + 16

            Column {
                anchors.fill: parent
                anchors.topMargin: -8
                anchors.bottomMargin: -8
                anchors.leftMargin: -8
                anchors.rightMargin: -8
                spacing: 0

                Repeater {
                    // City list with IANA tz identifiers. Offset + weekday
                    // are computed live from clockPage.nowDate via
                    // WorldClockHelper (QTimeZone, DST-correct) so no
                    // string math fights the DST boundaries.
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
                        width: parent.width
                        height: 72

                        readonly property var resolved: clockPage.timeIn(modelData.tz)

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                text: resolved.offsetLabel
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.weight: Font.Normal
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
                            anchors.rightMargin: 20
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                anchors.right: parent.right
                                text: resolved.time
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: 22
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
                            anchors.leftMargin: 20
                            anchors.right: parent.right
                            anchors.rightMargin: 20
                            height: 1
                            color: MColors.whiteOverlay04
                        }
                    }
                }
            }
        }
    }
}
