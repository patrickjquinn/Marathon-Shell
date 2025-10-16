import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Item {
    id: worldClockPage
    
    property var cities: [
        { name: "New York", offset: -5, dst: true },
        { name: "London", offset: 0, dst: false },
        { name: "Paris", offset: 1, dst: true },
        { name: "Tokyo", offset: 9, dst: false },
        { name: "Sydney", offset: 10, dst: false },
        { name: "Dubai", offset: 4, dst: false },
        { name: "Los Angeles", offset: -8, dst: true },
        { name: "Singapore", offset: 8, dst: false }
    ]
    
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            timeModel.updateTimes()
        }
    }
    
    ListModel {
        id: timeModel
        
        Component.onCompleted: {
            updateTimes()
        }
        
        function updateTimes() {
            clear()
            var now = new Date()
            for (var i = 0; i < cities.length; i++) {
                var city = cities[i]
                var cityTime = new Date(now.getTime() + (city.offset * 3600000))
                var hours = cityTime.getUTCHours()
                var minutes = cityTime.getUTCMinutes()
                var ampm = hours >= 12 ? "PM" : "AM"
                hours = hours % 12
                if (hours === 0) hours = 12
                var timeStr = hours + ":" + (minutes < 10 ? "0" : "") + minutes + " " + ampm
                
                append({
                    cityName: city.name,
                    cityTime: timeStr,
                    timeDiff: (city.offset >= 0 ? "+" : "") + city.offset + "h"
                })
            }
        }
    }
    
    ListView {
        anchors.fill: parent
        anchors.topMargin: Constants.spacingMedium
        clip: true
        model: timeModel
        spacing: 0
        
        delegate: Item {
            width: ListView.view.width
            height: Constants.touchTargetLarge
            
            Row {
                anchors.fill: parent
                anchors.leftMargin: Constants.spacingLarge
                anchors.rightMargin: Constants.spacingLarge
                spacing: Constants.spacingMedium
                
                Column {
                    width: parent.width - timeText.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Constants.spacingXSmall
                    
                    Text {
                        text: model.cityName
                        color: Colors.text
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: Font.DemiBold
                    }
                    
                    Text {
                        text: model.timeDiff
                        color: Colors.textSecondary
                        font.pixelSize: Constants.fontSizeSmall
                    }
                }
                
                Text {
                    id: timeText
                    anchors.verticalCenter: parent.verticalCenter
                    text: model.cityTime
                    color: Colors.accent
                    font.pixelSize: Constants.fontSizeLarge
                    font.weight: Font.Bold
                }
            }
            
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Constants.spacingLarge
                anchors.rightMargin: Constants.spacingLarge
                height: Constants.borderWidthThin
                color: Colors.border
            }
        }
    }
}

