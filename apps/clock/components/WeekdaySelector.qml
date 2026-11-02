pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../ClockLogic.js" as Logic

Grid {
    id: root

    property var days: []
    // Two rows when seven days would not fit a narrow column.
    readonly property int perRow: width / 7 >= Theme.iconSizeMedium ? 7 : 4

    x: Theme.horizontalPageMargin
    width: parent.width - 2 * Theme.horizontalPageMargin
    columns: perRow
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Repeat")

    Repeater {
        objectName: "weekdays"
        model: [1, 2, 3, 4, 5, 6, 0]

        BackgroundItem {
            id: day

            required property int modelData
            readonly property bool selected: root.days.indexOf(modelData) !== -1

            width: root.width / root.perRow
            height: Theme.itemSizeMedium
            Accessible.role: Accessible.CheckBox
            Accessible.name: Qt.locale().dayName(modelData)
            Accessible.checkable: true
            Accessible.checked: selected
            Accessible.onToggleAction: clicked(null)
            onClicked: root.days = Logic.toggleDay(root.days, modelData)

            GlassItem {
                id: dot

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: dayName.top
                anchors.bottomMargin: -Theme.paddingLarge
                color: day.down ? Theme.highlightColor : day.selected ? Theme.lightPrimaryColor : Theme.primaryColor
                backgroundColor: day.selected ? day.palette.backgroundGlowColor : "transparent"
                dimmed: !day.selected
                falloffRadius: day.selected ? defaultFalloffRadius : 0.075
            }
            Label {
                id: dayName

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.paddingSmall
                text: Qt.locale().dayName(day.modelData, Locale.ShortFormat)
                font.pixelSize: Theme.fontSizeSmall
                color: day.down ? Theme.highlightColor : Theme.primaryColor
            }
        }
    }
}
