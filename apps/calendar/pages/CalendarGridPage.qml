import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: calendarGridPage
    color: MColors.background
    
    property date selectedDate: new Date()
    property int currentMonth: selectedDate.getMonth()
    property int currentYear: selectedDate.getFullYear()
    
    function getDaysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }
    
    function getFirstDayOfMonth(year, month) {
        return new Date(year, month, 1).getDay()
    }
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Rectangle {
            width: parent.width
            height: Constants.touchTargetLarge + Constants.spacingLarge
            color: MColors.surface
            
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }
            
            Row {
                anchors.centerIn: parent
                spacing: Constants.spacingLarge
                
                MIconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "chevron-left"
                    size: Constants.touchTargetMedium
                    onClicked: {
                        if (currentMonth === 0) {
                            currentMonth = 11
                            currentYear--
                        } else {
                            currentMonth--
                        }
                        selectedDate = new Date(currentYear, currentMonth, 1)
                    }
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDate(selectedDate, "MMMM yyyy")
                    font.pixelSize: Constants.fontSizeLarge
                    font.weight: Font.Bold
                    color: MColors.text
                }
                
                MIconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "chevron-right"
                    size: Constants.touchTargetMedium
                    onClicked: {
                        if (currentMonth === 11) {
                            currentMonth = 0
                            currentYear++
                        } else {
                            currentMonth++
                        }
                        selectedDate = new Date(currentYear, currentMonth, 1)
                    }
                }
            }
        }
        
        Grid {
            width: parent.width
            height: parent.height - parent.children[0].height
            columns: 7
            rows: 7
            
            Repeater {
                model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                
                Rectangle {
                    width: calendarGridPage.width / 7
                    height: Constants.touchTargetMedium
                    color: MColors.surface2
                    
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: Constants.fontSizeSmall
                        font.weight: Font.Bold
                        color: MColors.textSecondary
                    }
                }
            }
            
            Repeater {
                model: 42
                
                Rectangle {
                    width: calendarGridPage.width / 7
                    height: (calendarGridPage.height - Constants.touchTargetLarge - Constants.spacingLarge - Constants.touchTargetMedium) / 6
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    
                    property int dayNumber: {
                        var firstDay = getFirstDayOfMonth(currentYear, currentMonth)
                        var dayIndex = index - firstDay
                        
                        if (dayIndex < 0) {
                            var prevMonth = currentMonth === 0 ? 11 : currentMonth - 1
                            var prevYear = currentMonth === 0 ? currentYear - 1 : currentYear
                            return getDaysInMonth(prevYear, prevMonth) + dayIndex + 1
                        } else if (dayIndex >= getDaysInMonth(currentYear, currentMonth)) {
                            return dayIndex - getDaysInMonth(currentYear, currentMonth) + 1
                        } else {
                            return dayIndex + 1
                        }
                    }
                    
                    property bool isCurrentMonth: {
                        var firstDay = getFirstDayOfMonth(currentYear, currentMonth)
                        var dayIndex = index - firstDay
                        return dayIndex >= 0 && dayIndex < getDaysInMonth(currentYear, currentMonth)
                    }
                    
                    property bool isToday: {
                        if (!isCurrentMonth) return false
                        var today = new Date()
                        return today.getDate() === dayNumber && 
                               today.getMonth() === currentMonth && 
                               today.getFullYear() === currentYear
                    }
                    
                    property var dayEvents: {
                        if (!isCurrentMonth) return []
                        var dayDate = new Date(currentYear, currentMonth, dayNumber)
                        return calendarApp.getEventsForDate(dayDate)
                    }
                    
                    Column {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingXSmall
                        spacing: Constants.spacingXSmall
                        
                        Rectangle {
                            width: Constants.touchTargetMedium
                            height: Constants.touchTargetMedium
                            radius: Constants.borderRadiusSharp
                            color: parent.parent.isToday ? MColors.accent : "transparent"
                            anchors.horizontalCenter: parent.horizontalCenter
                            
                            Text {
                                anchors.centerIn: parent
                                text: parent.parent.parent.dayNumber
                                font.pixelSize: Constants.fontSizeSmall
                                font.weight: parent.parent.parent.isToday ? Font.Bold : Font.Normal
                                color: parent.parent.parent.isCurrentMonth ? (parent.parent.parent.isToday ? MColors.text : MColors.text) : MColors.textTertiary
                            }
                        }
                        
                        Repeater {
                            model: Math.min(parent.parent.dayEvents.length, 3)
                            
                            Rectangle {
                                width: parent.width
                                height: Constants.spacingMedium
                                radius: Constants.borderRadiusSharp
                                color: MColors.accent
                                
                                Text {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    text: parent.parent.parent.dayEvents[index].title
                                    font.pixelSize: Constants.fontSizeXSmall
                                    color: MColors.text
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 2
                                }
                            }
                        }
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: parent.parent.dayEvents.length > 3 ? "+" + (parent.parent.dayEvents.length - 3) : ""
                            font.pixelSize: Constants.fontSizeXSmall
                            color: MColors.textSecondary
                            visible: parent.parent.dayEvents.length > 3
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (parent.isCurrentMonth) {
                                Logger.info("Calendar", "Clicked date: " + parent.dayNumber)
                            }
                        }
                    }
                }
            }
        }
    }
}

