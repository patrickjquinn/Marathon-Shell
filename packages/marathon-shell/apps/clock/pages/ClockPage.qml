import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components" as ClockComponents

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
            var now = new Date()
            hours = now.getHours()
            minutes = now.getMinutes()
            seconds = now.getSeconds()
            
            // Format date for 3 o'clock position
            dayOfMonth = now.getDate().toString()
            var days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
            dayOfWeek = days[now.getDay()]
        }
    }
    
    Rectangle {
        anchors.fill: parent
        color: Colors.background
        
        // Main analog clock - centered and large
        Item {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.85, parent.height * 0.7)
            height: width
            
            // Squircle clock face (super-ellipse shape) - larger frame ONLY
            Rectangle {
                id: clockFace
                anchors.centerIn: parent
                width: parent.width * 1.10  // 10% larger frame (smaller than before)
                height: parent.height * 1.10
                color: Colors.background
                border.width: Constants.borderWidthThick
                border.color: Qt.rgba(0.18, 0.18, 0.18, 1.0)  // Darker, more subtle gray border
                radius: width * 0.22  // Squircle-like radius (22% of width)
                
                // Scale factor to keep clock content same size inside larger frame
                property real contentScale: 1.0 / 1.10
                
                // Container to scale clock content to original size
                Item {
                    anchors.centerIn: parent
                    width: parent.width * parent.contentScale
                    height: parent.height * parent.contentScale
                
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
                                anchors.topMargin: Constants.spacingMedium
                                
                                width: isHourMarker ? Constants.borderWidthThick : Constants.borderWidthThin
                                height: isHourMarker ? Constants.spacingMedium : Constants.spacingSmall
                                color: Colors.accent
                            }
                        }
                    }
                
                    // Number: 12
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: Constants.spacingXLarge
                        text: "12"
                        font.pixelSize: Constants.fontSizeXXLarge
                        font.weight: Font.Bold
                        color: Colors.accent
                    }
                    
                    // Number: 3 with date
                    Column {
                        anchors.right: parent.right
                        anchors.rightMargin: Constants.spacingXLarge
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Constants.spacingXSmall
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayOfMonth
                            font.pixelSize: Constants.fontSizeMedium
                            font.weight: Font.Normal
                            color: Colors.accent
                        }
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: dayOfWeek
                            font.pixelSize: Constants.fontSizeSmall
                            font.weight: Font.Normal
                            color: Colors.accent
                        }
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "3"
                            font.pixelSize: Constants.fontSizeXXLarge
                            font.weight: Font.Bold
                            color: Colors.accent
                        }
                    }
                    
                    // Number: 6
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Constants.spacingXLarge
                        text: "6"
                        font.pixelSize: Constants.fontSizeXXLarge
                        font.weight: Font.Bold
                        color: Colors.accent
                    }
                    
                    // Number: 9
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Constants.spacingXLarge
                        anchors.verticalCenter: parent.verticalCenter
                        text: "9"
                        font.pixelSize: Constants.fontSizeXXLarge
                        font.weight: Font.Bold
                        color: Colors.accent
                    }
                    
                    // PM indicator
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: Constants.spacingXLarge * 1.5
                        text: hours >= 12 ? "PM" : "AM"
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: Font.Normal
                        color: Colors.accent
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
                            color: Colors.accent
                        }
                    }
                    
                    // Center pivot point - circular
                    Rectangle {
                        anchors.centerIn: parent
                        width: Constants.spacingMedium
                        height: Constants.spacingMedium
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
            color: Colors.background
            visible: clockApp.alarms.length > 0
            
            Column {
                anchors.left: parent.left
                anchors.leftMargin: Constants.spacingLarge
                anchors.verticalCenter: parent.verticalCenter
                spacing: Constants.spacingXSmall
                
                Row {
                    spacing: Constants.spacingSmall
                    
                    Text {
                        text: {
                            if (clockApp.alarms.length === 0) return ""
                            var alarm = clockApp.alarms[0]
                            var h = alarm.hour % 12
                            if (h === 0) h = 12
                            var m = alarm.minute < 10 ? "0" + alarm.minute : alarm.minute
                            return h + ":" + m
                        }
                        font.pixelSize: Constants.fontSizeLarge
                        font.weight: Font.Normal
                        color: Colors.text
                    }
                    
                    Text {
                        text: clockApp.alarms.length > 0 && clockApp.alarms[0].label ? clockApp.alarms[0].label : "Alarm Off"
                        font.pixelSize: Constants.fontSizeLarge
                        font.weight: Font.Normal
                        color: Colors.text
                    }
                }
                
                Text {
                    text: "No Recurrence"
                    font.pixelSize: Constants.fontSizeSmall
                    color: Colors.accent
                }
            }
            
            // Alarm toggle
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Constants.spacingLarge
                anchors.verticalCenter: parent.verticalCenter
                width: Constants.touchTargetMedium
                height: Constants.touchTargetMedium
                radius: width / 2
                color: Colors.surface
                
                ClockComponents.ClockIcon {
                    anchors.centerIn: parent
                    name: "clock"
                    size: Constants.iconSizeMedium
                    color: Colors.textSecondary
                }
            }
        }
    }
}
