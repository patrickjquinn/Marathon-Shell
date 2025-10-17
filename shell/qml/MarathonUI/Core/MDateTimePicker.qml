import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Rectangle {
    id: root
    
    property date selectedDate: new Date()
    property string mode: "date"
    property string label: ""
    
    signal dateSelected(date date)
    
    implicitWidth: 200
    implicitHeight: Constants.touchTargetMedium
    
    color: MElevation.getSurface(1)
    radius: Constants.borderRadiusSharp
    border.width: Constants.borderWidthThin
    border.color: MElevation.getBorderOuter(1)
    antialiasing: Constants.enableAntialiasing
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: Constants.borderWidthThin
        radius: parent.radius - Constants.borderWidthThin
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MElevation.getBorderInner(1)
        antialiasing: Constants.enableAntialiasing
    }
    
    MouseArea {
        anchors.fill: parent
        onClicked: pickerSheet.show()
    }
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingMedium
        anchors.rightMargin: Constants.spacingMedium
        spacing: Constants.spacingSmall
        
        Icon {
            name: root.mode === "date" ? "calendar" : "clock"
            size: Constants.iconSizeMedium
            color: MColors.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }
        
        Text {
            text: {
                if (root.mode === "date") {
                    return Qt.formatDate(root.selectedDate, "MMM dd, yyyy")
                } else if (root.mode === "time") {
                    return Qt.formatTime(root.selectedDate, "hh:mm AP")
                } else {
                    return Qt.formatDateTime(root.selectedDate, "MMM dd, yyyy hh:mm AP")
                }
            }
            font.pixelSize: Constants.fontSizeMedium
            color: MColors.text
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: parent.width - parent.spacing - Constants.iconSizeMedium
        }
    }
    
    MSheet {
        id: pickerSheet
        title: root.label || (root.mode === "date" ? "Select Date" : "Select Time")
        anchors.fill: parent
        
        content: [
            Column {
                width: parent.width
                spacing: Constants.spacingLarge
                
                Row {
                    spacing: Constants.spacingSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    Tumbler {
                        id: monthTumbler
                        visible: root.mode !== "time"
                        model: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                        currentIndex: root.selectedDate.getMonth()
                        delegate: Text {
                            text: modelData
                            font.pixelSize: Constants.fontSizeLarge
                            color: MColors.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        }
                    }
                    
                    Tumbler {
                        id: dayTumbler
                        visible: root.mode !== "time"
                        model: 31
                        currentIndex: root.selectedDate.getDate() - 1
                        delegate: Text {
                            text: modelData + 1
                            font.pixelSize: Constants.fontSizeLarge
                            color: MColors.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        }
                    }
                    
                    Tumbler {
                        id: yearTumbler
                        visible: root.mode !== "time"
                        model: 100
                        currentIndex: root.selectedDate.getFullYear() - 1950
                        delegate: Text {
                            text: modelData + 1950
                            font.pixelSize: Constants.fontSizeLarge
                            color: MColors.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        }
                    }
                    
                    Tumbler {
                        id: hourTumbler
                        visible: root.mode !== "date"
                        model: 12
                        currentIndex: root.selectedDate.getHours() % 12
                        delegate: Text {
                            text: modelData === 0 ? 12 : modelData
                            font.pixelSize: Constants.fontSizeLarge
                            color: MColors.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        }
                    }
                    
                    Text {
                        visible: root.mode !== "date"
                        text: ":"
                        font.pixelSize: Constants.fontSizeXLarge
                        color: MColors.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Tumbler {
                        id: minuteTumbler
                        visible: root.mode !== "date"
                        model: 60
                        currentIndex: root.selectedDate.getMinutes()
                        delegate: Text {
                            text: modelData < 10 ? "0" + modelData : modelData
                            font.pixelSize: Constants.fontSizeLarge
                            color: MColors.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        }
                    }
                    
                    Tumbler {
                        id: ampmTumbler
                        visible: root.mode !== "date"
                        model: ["AM", "PM"]
                        currentIndex: root.selectedDate.getHours() >= 12 ? 1 : 0
                        delegate: Text {
                            text: modelData
                            font.pixelSize: Constants.fontSizeLarge
                            color: MColors.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2)
                        }
                    }
                }
                
                Row {
                    spacing: Constants.spacingMedium
                    anchors.horizontalCenter: parent.horizontalCenter
                    
                    MButton {
                        text: "Cancel"
                        variant: "secondary"
                        onClicked: pickerSheet.close()
                    }
                    
                    MButton {
                        text: "Done"
                        variant: "primary"
                        onClicked: {
                            var newDate = new Date(root.selectedDate)
                            
                            if (root.mode !== "time") {
                                newDate.setFullYear(yearTumbler.currentIndex + 1950)
                                newDate.setMonth(monthTumbler.currentIndex)
                                newDate.setDate(dayTumbler.currentIndex + 1)
                            }
                            
                            if (root.mode !== "date") {
                                var hour = hourTumbler.currentIndex
                                if (ampmTumbler.currentIndex === 1) {
                                    hour += 12
                                }
                                if (hour === 12) hour = 0
                                if (hour === 24) hour = 12
                                newDate.setHours(hour)
                                newDate.setMinutes(minuteTumbler.currentIndex)
                            }
                            
                            root.selectedDate = newDate
                            root.dateSelected(newDate)
                            pickerSheet.close()
                        }
                    }
                }
            }
        ]
    }
}

