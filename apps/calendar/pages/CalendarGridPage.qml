import MarathonApp.Calendar
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Calendar Month (screens-apps-2.jsx:CalendarApp).
//
// Display-weight month title + inline search/+ actions. Month grid
// uses single-letter weekday headings, today is a solid teal-bright
// square with black numeral, days with events show teal dots beneath
// the numeral. Selected-day agenda inlines beneath the grid:
// eyebrow header, then time+duration | vertical accent | title.
Rectangle {
    id: calendarGridPage

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
        return calendarApp.getEventsForDate(selectedDate);
    }

    color: MColors.background

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header — Display month title + compose ─────────────
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

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                // 36 × 36 teal-gradient compose squircle.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: MRadius.md
                    border.width: 1
                    border.color: MColors.tealBorder
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: MColors.marathonTealBright
                        }
                        GradientStop {
                            position: 1
                            color: MColors.marathonTealDark
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: 20
                        color: "#000000"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium();
                            if (calendarApp.navStack)
                                calendarApp.navStack.push("pages/EventCreationPage.qml", {
                                    "saveCallback": event => {
                                        calendarApp.createEvent(event.title, event.date, event.time, event.allDay, event.recurring);
                                    }
                                });
                        }
                    }
                }
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
                spacing: 12

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-left"
                    size: 18
                    color: MColors.textSecondary
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: {
                            HapticService.light();
                            if (currentMonth === 0) {
                                currentMonth = 11;
                                currentYear--;
                            } else {
                                currentMonth--;
                            }
                            selectedDate = new Date(currentYear, currentMonth, 1);
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
                        anchors.margins: -8
                        onClicked: {
                            HapticService.light();
                            const today = new Date();
                            currentMonth = today.getMonth();
                            currentYear = today.getFullYear();
                            selectedDate = today;
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
                        anchors.margins: -10
                        onClicked: {
                            HapticService.light();
                            if (currentMonth === 11) {
                                currentMonth = 0;
                                currentYear++;
                            } else {
                                currentMonth++;
                            }
                            selectedDate = new Date(currentYear, currentMonth, 1);
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
                    width: calendarGridPage.width / 7
                    height: 28
                    Text {
                        anchors.centerIn: parent
                        text: modelData
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

                    property int dayNumber: {
                        const firstDay = getFirstDayOfMonth(currentYear, currentMonth);
                        const dayIndex = index - firstDay;
                        if (dayIndex < 0) {
                            const prevMonth = currentMonth === 0 ? 11 : currentMonth - 1;
                            const prevYear = currentMonth === 0 ? currentYear - 1 : currentYear;
                            return getDaysInMonth(prevYear, prevMonth) + dayIndex + 1;
                        } else if (dayIndex >= getDaysInMonth(currentYear, currentMonth)) {
                            return dayIndex - getDaysInMonth(currentYear, currentMonth) + 1;
                        }
                        return dayIndex + 1;
                    }
                    property bool isCurrentMonth: {
                        const firstDay = getFirstDayOfMonth(currentYear, currentMonth);
                        const dayIndex = index - firstDay;
                        return dayIndex >= 0 && dayIndex < getDaysInMonth(currentYear, currentMonth);
                    }
                    property bool isToday: {
                        if (!isCurrentMonth)
                            return false;
                        const today = new Date();
                        return today.getDate() === dayNumber && today.getMonth() === currentMonth && today.getFullYear() === currentYear;
                    }
                    property bool isSelected: isCurrentMonth && calendarGridPage.isSameDay(calendarGridPage.selectedDate, new Date(currentYear, currentMonth, dayNumber))
                    property var dayEvents: {
                        if (!isCurrentMonth)
                            return [];
                        const d = new Date(currentYear, currentMonth, dayNumber);
                        return calendarApp.getEventsForDate(d);
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
                        onClicked: {
                            if (parent.isCurrentMonth) {
                                HapticService.light();
                                calendarGridPage.selectedDate = new Date(currentYear, currentMonth, parent.dayNumber);
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
                message: "Tap + to add one for this day"
            }

            ListView {
                id: agendaList
                anchors.fill: parent
                visible: count > 0
                clip: true
                spacing: 8
                model: calendarGridPage.selectedEvents()

                // Agenda re-fetches when month/day/events change.
                Connections {
                    target: calendarApp
                    function onEventsChanged() {
                        calendarGridPage.modelStale = !calendarGridPage.modelStale;
                    }
                }

                delegate: Rectangle {
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
                                text: modelData.time || ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Bold
                                font.features: ({
                                        "tnum": 1
                                    })
                            }
                            Text {
                                text: modelData.duration || ""
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
                                text: modelData.title || ""
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: modelData.category || ""
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
                        onClicked: calendarApp.openEventDetail(modelData)
                    }
                }
            }
        }
    }

    property bool modelStale: false
}
