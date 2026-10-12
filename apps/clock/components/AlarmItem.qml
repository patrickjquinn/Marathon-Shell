import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Theme
import QtQuick

Item {
    id: alarmItem

    property string alarmId: ""
    property int alarmHour: 0
    property int alarmMinute: 0
    property string alarmLabel: "Alarm"
    property bool alarmEnabled: true
    property var alarmRepeat: []

    signal toggled
    signal clicked

    function repeatSummary(days) {
        if (days.length === 7)
            return "Every day";
        const key = days.slice().sort().join(",");
        if (key === "1,2,3,4,5")
            return "Weekdays";
        if (key === "0,6")
            return "Weekends";
        return [1, 2, 3, 4, 5, 6, 0].filter(d => days.indexOf(d) !== -1).map(d => Qt.locale().dayName(d, Locale.ShortFormat)).join(" ");
    }

    function formatTime(hour, minute) {
        var h = hour;
        var suffix = "AM";
        if (h >= 12) {
            suffix = "PM";
            if (h > 12)
                h -= 12;
        }
        if (h === 0)
            h = 12;

        return h + ":" + (minute < 10 ? "0" : "") + minute + " " + suffix;
    }

    height: card.height + MSpacing.md

    MCard {
        id: card

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: MSpacing.lg
        anchors.rightMargin: MSpacing.lg
        elevation: 1
        interactive: true
        onClicked: alarmItem.clicked()

        Row {
            width: parent.parent.width - MSpacing.md * 2
            height: MSpacing.touchTargetLarge
            spacing: MSpacing.md

            Column {
                width: parent.width - toggleSwitch.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: MSpacing.xs

                Text {
                    text: alarmItem.formatTime(alarmItem.alarmHour, alarmItem.alarmMinute)
                    color: alarmItem.alarmEnabled ? MColors.text : MColors.textSecondary
                    font.pixelSize: MTypography.sizeXLarge
                    font.weight: MTypography.weightBold
                    font.family: MTypography.fontFamily
                }

                Text {
                    width: parent.width
                    text: alarmItem.alarmRepeat.length > 0 ? alarmItem.alarmLabel + " · " + alarmItem.repeatSummary(alarmItem.alarmRepeat) : alarmItem.alarmLabel
                    elide: Text.ElideRight
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                }
            }

            MToggle {
                id: toggleSwitch

                anchors.verticalCenter: parent.verticalCenter
                checked: alarmItem.alarmEnabled
                a11yName: "Alarm at " + alarmItem.formatTime(alarmItem.alarmHour, alarmItem.alarmMinute)
                onToggled: {
                    alarmItem.toggled();
                }
            }
        }
    }
}
