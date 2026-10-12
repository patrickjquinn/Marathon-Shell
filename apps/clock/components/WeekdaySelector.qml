import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

Row {
    id: root

    property var days: []

    x: Theme.horizontalPageMargin
    width: parent.width - 2 * Theme.horizontalPageMargin
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Repeat")

    Repeater {
        objectName: "weekdays"
        model: [1, 2, 3, 4, 5, 6, 0]

        BackgroundItem {
            id: day

            required property int modelData
            readonly property bool selected: root.days.indexOf(modelData) !== -1

            width: root.width / 7
            height: Theme.itemSizeSmall
            highlighted: down || selected
            Accessible.role: Accessible.CheckBox
            Accessible.name: Qt.locale().dayName(modelData)
            Accessible.checkable: true
            Accessible.checked: selected
            Accessible.onToggleAction: clicked(null)
            onClicked: root.days = Logic.toggleDay(root.days, modelData)

            Label {
                anchors.centerIn: parent
                text: Qt.locale().dayName(day.modelData, Locale.ShortFormat)
                font.pixelSize: Theme.fontSizeSmall
                color: day.selected ? Theme.highlightColor : Theme.primaryColor
            }
        }
    }
}
