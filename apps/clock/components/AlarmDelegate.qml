import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

ListItem {
    id: root

    required property var modelData
    property var app

    readonly property var time: Logic.parseTime(modelData.time)
    readonly property string timeText: Format.formatDate(new Date(0, 0, 0, time.hour, time.minute), Formatter.TimeValue)
    readonly property string repeatText: Logic.repeatSummary(modelData.repeat || [], d => Qt.locale().dayName(d, Locale.ShortFormat))

    objectName: "alarmItem"
    contentHeight: Theme.itemSizeLarge
    Accessible.name: [timeText, modelData.label || qsTr("Alarm"), repeatText].filter(s => s).join(", ")
    menu: ContextMenu {
        MenuItem {
            objectName: "editAlarm"
            text: qsTr("Edit")
            onClicked: root.app.editAlarm(root.modelData)
        }
        MenuItem {
            text: qsTr("Delete")
            onClicked: {
                const app = root.app;
                const id = root.modelData.id;
                root.remorseDelete(() => app.deleteAlarm(id));
            }
        }
    }
    onClicked: app.toggleAlarm(modelData.id)

    Switch {
        id: toggle

        objectName: "alarmSwitch"
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.horizontalPageMargin - Theme.paddingLarge
        automaticCheck: false
        checked: root.modelData.enabled
        highlighted: down || root.highlighted
        Accessible.name: qsTr("Alarm at %1").arg(root.timeText)
        onClicked: root.app.toggleAlarm(root.modelData.id)
    }

    Column {
        anchors {
            left: toggle.right
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }

        Label {
            text: root.timeText
            font.pixelSize: Theme.fontSizeExtraLarge
            color: root.highlighted || root.modelData.enabled ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            width: parent.width
            text: [root.modelData.label || qsTr("Alarm"), root.repeatText].filter(s => s).join(" · ")
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
            color: root.highlighted || root.modelData.enabled ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }
}
