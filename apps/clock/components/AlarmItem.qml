import QtQuick
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Containers
import MarathonUI.Theme

Item {
    id: alarmItem
    height: card.height + MSpacing.md

    property int alarmId: -1
    property int alarmHour: 0
    property int alarmMinute: 0
    property string alarmLabel: "Alarm"
    property bool alarmEnabled: true

    signal toggled
    signal deleted
    signal clicked

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
                    text: formatTime(alarmHour, alarmMinute)
                    color: alarmEnabled ? MColors.text : MColors.textSecondary
                    font.pixelSize: MTypography.sizeXLarge
                    font.weight: MTypography.weightBold
                    font.family: MTypography.fontFamily
                }

                Text {
                    text: alarmLabel
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeSmall
                    font.family: MTypography.fontFamily
                }
            }

            MToggle {
                id: toggleSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: alarmEnabled
                onToggled: {
                    alarmItem.toggled();
                }
            }
        }
    }
}
