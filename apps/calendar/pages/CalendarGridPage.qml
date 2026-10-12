pragma ComponentBehavior: Bound
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Calendar Month (screens-apps-2.jsx:CalendarApp).
//
// Display-weight month title; compose is the app's FAB. Month grid
// uses single-letter weekday headings, today is a solid teal-bright
// square with black numeral, days with events show teal dots beneath
// the numeral. Selected-day agenda inlines beneath the grid:
// eyebrow header, then time+duration | vertical accent | title.
Rectangle {
    id: calendarGridPage

    required property var app
    property date selectedDate: new Date()
    property int currentMonth: selectedDate.getMonth()
    property int currentYear: selectedDate.getFullYear()

    function getDaysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate();
    }
    function getFirstDayOfMonth(year, month) {
        // ISO week — Monday-first, matches JSX "M T W T F S S" order.
        const js = new Date(year, month, 1).getDay();
        return js === 0 ? 6 : js - 1;
    }
    function isSameDay(a, b) {
        return a && b && a.getDate() === b.getDate() && a.getMonth() === b.getMonth() && a.getFullYear() === b.getFullYear();
    }
    function selectedEvents() {
        return app.getEventsForDate(selectedDate);
    }
    function showMonth(year, month) {
        currentMonth = month;
        currentYear = year;
        selectedDate = new Date(year, month, 1);
    }

    color: MColors.background

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header — Display month title ───────────────────────
        Item {
            width: parent.width
            height: 96

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(calendarGridPage.selectedDate, "MMMM")
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: 48
                font.weight: MTypography.weightExtraLight   // 200 per DS Title L
                font.letterSpacing: -1.2
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: MColors.borderGlass
            }
        }

        // ── Year + Today nav row ─────────────────────────────
        Item {
            width: parent.width
            height: 44

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(calendarGridPage.selectedDate, "yyyy")
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeSubhead
                font.weight: Font.Normal
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: MSpacing.lg

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-left"
                    size: 18
                    color: MColors.textSecondary
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -(MSpacing.touchTargetMin - parent.width) / 2
                        Accessible.role: Accessible.Button
                        Accessible.name: "Previous month"
                        Accessible.onPressAction: clicked(null)
                        onClicked: {
                            HapticService.light();
                            if (calendarGridPage.currentMonth === 0) {
                                calendarGridPage.currentMonth = 11;
                                calendarGridPage.currentYear--;
                            } else {
                                calendarGridPage.currentMonth--;
                            }
                            calendarGridPage.selectedDate = new Date(calendarGridPage.currentYear, calendarGridPage.currentMonth, 1);
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Today"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    font.weight: Font.Medium
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -MSpacing.sm
                        anchors.topMargin: -(MSpacing.touchTargetMin - parent.height) / 2
                        anchors.bottomMargin: -(MSpacing.touchTargetMin - parent.height) / 2
                        Accessible.role: Accessible.Button
                        Accessible.name: "Go to today"
                        Accessible.onPressAction: clicked(null)
                        onClicked: {
                            HapticService.light();
                            const today = new Date();
                            calendarGridPage.currentMonth = today.getMonth();
                            calendarGridPage.currentYear = today.getFullYear();
                            calendarGridPage.selectedDate = today;
                        }
                    }
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-right"
                    size: 18
                    color: MColors.textSecondary
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -(MSpacing.touchTargetMin - parent.width) / 2
                        Accessible.role: Accessible.Button
                        Accessible.name: "Next month"
                        Accessible.onPressAction: clicked(null)
                        onClicked: {
                            HapticService.light();
                            if (calendarGridPage.currentMonth === 11) {
                                calendarGridPage.currentMonth = 0;
                                calendarGridPage.currentYear++;
                            } else {
                                calendarGridPage.currentMonth++;
                            }
                            calendarGridPage.selectedDate = new Date(calendarGridPage.currentYear, calendarGridPage.currentMonth, 1);
                        }
                    }
                }
            }
        }

        // ── Weekday headers — single-letter M T W T F S S ────
        // Use textSecondary (not textTertiary) so the header letters are
        // visually distinct from the next-month days in the grid — those
        // also render at tertiary, which made the M T W T F S S row read
        // as more "greyed out" days rather than as a column header.
        Row {
            width: parent.width
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                Item {
                    id: weekdayLabel

                    required property string modelData

                    width: calendarGridPage.width / 7
                    height: 28
                    Text {
                        anchors.centerIn: parent
                        text: weekdayLabel.modelData
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: Font.Bold
                        font.letterSpacing: MTypography.trackingEyebrow
                    }
                }
            }
        }

        // ── Month grid — 6 rows × 7 cols, today = teal square ──
        Grid {
            width: parent.width
            columns: 7

            Repeater {
                model: 42

                Item {
                    id: dayCell

                    required property int index

                    property int dayNumber: {
                        const firstDay = calendarGridPage.getFirstDayOfMonth(calendarGridPage.currentYear, calendarGridPage.currentMonth);
                        const dayIndex = index - firstDay;
                        if (dayIndex < 0) {
                            const prevMonth = calendarGridPage.currentMonth === 0 ? 11 : calendarGridPage.currentMonth - 1;
                            const prevYear = calendarGridPage.currentMonth === 0 ? calendarGridPage.currentYear - 1 : calendarGridPage.currentYear;
                            return calendarGridPage.getDaysInMonth(prevYear, prevMonth) + dayIndex + 1;
                        } else if (dayIndex >= calendarGridPage.getDaysInMonth(calendarGridPage.currentYear, calendarGridPage.currentMonth)) {
                            return dayIndex - calendarGridPage.getDaysInMonth(calendarGridPage.currentYear, calendarGridPage.currentMonth) + 1;
                        }
                        return dayIndex + 1;
                    }
                    property bool isCurrentMonth: {
                        const firstDay = calendarGridPage.getFirstDayOfMonth(calendarGridPage.currentYear, calendarGridPage.currentMonth);
                        const dayIndex = index - firstDay;
                        return dayIndex >= 0 && dayIndex < calendarGridPage.getDaysInMonth(calendarGridPage.currentYear, calendarGridPage.currentMonth);
                    }
                    property bool isToday: {
                        if (!isCurrentMonth)
                            return false;
                        const today = new Date();
                        return today.getDate() === dayNumber && today.getMonth() === calendarGridPage.currentMonth && today.getFullYear() === calendarGridPage.currentYear;
                    }
                    property bool isSelected: isCurrentMonth && calendarGridPage.isSameDay(calendarGridPage.selectedDate, new Date(calendarGridPage.currentYear, calendarGridPage.currentMonth, dayNumber))
                    property var dayEvents: {
                        calendarGridPage.modelStale;
                        if (!isCurrentMonth)
                            return [];
                        const d = new Date(calendarGridPage.currentYear, calendarGridPage.currentMonth, dayNumber);
                        return calendarGridPage.app.getEventsForDate(d);
                    }

                    width: calendarGridPage.width / 7
                    height: 56

                    // Today highlight — solid teal square in cell.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: MRadius.md
                        color: dayCell.isToday ? MColors.marathonTealBright : (dayCell.isSelected ? MColors.elev2 : "transparent")
                        border.width: dayCell.isSelected && !dayCell.isToday ? 1 : 0
                        border.color: MColors.tealBorder

                        Text {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.topMargin: 6
                            anchors.leftMargin: 8
                            text: dayCell.dayNumber
                            color: dayCell.isToday ? "#000000" : (dayCell.isCurrentMonth ? MColors.textPrimary : MColors.textTertiary)
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeSubhead
                            font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                        }

                        // Event dots — up to 3 teal-bright 4 px circles.
                        Row {
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            Repeater {
                                model: Math.min(dayCell.dayEvents.length, 3)
                                Rectangle {
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: dayCell.isToday ? "#000000" : MColors.marathonTealBright
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        Accessible.role: Accessible.Button
                        Accessible.name: Qt.formatDate(new Date(calendarGridPage.currentYear, calendarGridPage.currentMonth, dayCell.dayNumber), "dddd, MMMM d") + (dayCell.dayEvents.length > 0 ? ", " + dayCell.dayEvents.length + (dayCell.dayEvents.length === 1 ? " event" : " events") : "")
                        Accessible.ignored: !dayCell.isCurrentMonth
                        Accessible.onPressAction: calendarGridPage.selectedDate = new Date(calendarGridPage.currentYear, calendarGridPage.currentMonth, dayCell.dayNumber)
                        onClicked: {
                            if (parent.isCurrentMonth) {
                                HapticService.light();
                                calendarGridPage.selectedDate = new Date(calendarGridPage.currentYear, calendarGridPage.currentMonth, parent.dayNumber);
                                calendarGridPage.app.selectedDate = calendarGridPage.selectedDate;
                            }
                        }
                    }
                }
            }
        }

        // ── Selected-day agenda ─────────────────────────────
        Item {
            width: parent.width
            height: 14
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 20
            text: Qt.formatDate(calendarGridPage.selectedDate, "dddd, MMMM d").toUpperCase()
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeEyebrow
            font.weight: Font.Bold
            font.letterSpacing: MTypography.trackingEyebrow
        }

        Item {
            width: parent.width
            height: 10
        }

        Item {
            id: agendaArea
            width: parent.width
            height: parent.height - height_above()
            function height_above() {
                return 96 + 44 + 28 + 56 * 6 + 14 + 24 + 10;
            }

            MEmptyState {
                anchors.centerIn: parent
                width: parent.width - 48
                visible: agendaList.count === 0
                iconName: "calendar"
                iconSize: 48
                title: "No events"
                message: "Tap New event to add one for this day."
            }

            ListView {
                id: agendaList
                anchors.fill: parent
                visible: count > 0
                clip: true
                spacing: 8
                bottomMargin: Math.round(64 * Constants.scaleFactor) + MSpacing.lg * 2
                model: {
                    calendarGridPage.modelStale;
                    return calendarGridPage.selectedEvents();
                }

                // Agenda re-fetches when month/day/events change.
                Connections {
                    target: calendarGridPage.app
                    function onEventsChanged() {
                        calendarGridPage.modelStale = !calendarGridPage.modelStale;
                    }
                }

                delegate: Rectangle {
                    id: agendaItem

                    required property var modelData

                    width: ListView.view.width - 40
                    anchors.left: parent ? parent.left : undefined
                    anchors.leftMargin: 20
                    height: 70
                    radius: MRadius.md
                    color: MColors.elev2
                    border.width: 1
                    border.color: MColors.whiteOverlay04

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 60
                            spacing: 2
                            Text {
                                text: agendaItem.modelData.time || ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Bold
                                font.features: ({
                                        "tnum": 1
                                    })
                            }
                            Text {
                                text: agendaItem.modelData.duration || ""
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.features: ({
                                        "tnum": 1
                                    })
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 2
                            height: 46
                            color: MColors.marathonTealBright
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 60 - 2 - parent.spacing * 2
                            spacing: 2
                            Text {
                                width: parent.width
                                text: agendaItem.modelData.title || ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: agendaItem.modelData.category || ""
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        Accessible.role: Accessible.Button
                        Accessible.name: (agendaItem.modelData.title || "Untitled Event") + ", " + (agendaItem.modelData.allDay ? "all day" : agendaItem.modelData.time)
                        Accessible.onPressAction: calendarGridPage.app.openEventDetail(agendaItem.modelData)
                        onClicked: calendarGridPage.app.openEventDetail(agendaItem.modelData)
                    }
                }
            }
        }
    }

    property bool modelStale: false
}
