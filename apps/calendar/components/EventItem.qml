import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../CalendarLogic.js" as Logic

ListItem {
    id: item

    required property var modelData
    property var app
    property bool showDate: false

    objectName: "eventItem"
    width: parent ? parent.width : 0
    contentHeight: Theme.itemSizeMedium
    readonly property string details: [showDate ? app.dateText(modelData) : modelData.recurring && modelData.recurring !== "none" ? app.repeatText(modelData.recurring) : "", modelData.location || ""].filter(s => s !== "").join(" · ")

    Accessible.name: [modelData.title || qsTr("Untitled event"), showDate ? app.dateText(modelData) : "", app.timeRangeText(modelData), modelData.location || ""].filter(s => s !== "").join(", ")
    onClicked: app.openEvent(modelData)
    menu: ContextMenu {
        MenuItem {
            objectName: "editItem"
            text: qsTr("Edit")
            onClicked: item.app.editEvent(item.modelData)
        }
        MenuItem {
            objectName: "deleteItem"
            text: qsTr("Delete")
            onClicked: {
                const id = item.modelData.id;
                item.remorseDelete(function () {
                    item.app.deleteEvent(id);
                });
            }
        }
    }

    Column {
        id: timeColumn

        x: Theme.horizontalPageMargin
        width: Theme.itemSizeExtraLarge
        anchors.verticalCenter: parent.verticalCenter

        Label {
            width: parent.width
            text: item.app.timeText(item.modelData)
            font.pixelSize: Theme.fontSizeSmall
            font.features: ({
                    "tnum": 1
                })
            truncationMode: TruncationMode.Fade
            color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
        Label {
            objectName: "endTimeLabel"
            width: parent.width
            visible: text !== ""
            text: {
                if (item.modelData.allDay || !item.modelData.endTime)
                    return "";
                const t = Logic.parseTime(item.modelData.endTime);
                return Format.formatDate(new Date(2000, 0, 1, t.hour, t.minute), Formatter.TimeValue);
            }
            font.pixelSize: Theme.fontSizeExtraSmall
            font.features: ({
                    "tnum": 1
                })
            truncationMode: TruncationMode.Fade
            color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }

    Rectangle {
        id: bar

        anchors {
            left: timeColumn.right
            leftMargin: Theme.paddingMedium
            verticalCenter: parent.verticalCenter
        }
        width: Math.round(Theme.paddingSmall / 2)
        height: parent.height - 2 * Theme.paddingMedium
        radius: width / 2
        color: Theme.highlightColor
    }

    Column {
        anchors {
            left: bar.right
            leftMargin: Theme.paddingMedium
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: item.modelData.title || qsTr("Untitled event")
            truncationMode: TruncationMode.Fade
            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            width: parent.width
            visible: text !== ""
            text: item.details
            font.pixelSize: Theme.fontSizeExtraSmall
            truncationMode: TruncationMode.Fade
            color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }
}
