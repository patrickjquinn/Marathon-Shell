import QtQuick
import MarathonUI.Core
import MarathonUI.Theme

Item {
    id: root

    property date messageDate

    width: parent.width
    height: 40

    Row {
        anchors.centerIn: parent
        spacing: MSpacing.sm

        Rectangle {
            width: 40
            height: 1
            color: MColors.border
            anchors.verticalCenter: parent.verticalCenter
        }

        MLabel {
            text: formatDate(messageDate)
            variant: "tertiary"
            font.pixelSize: MTypography.sizeXSmall
            font.weight: MTypography.weightMedium
            anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
            width: 40
            height: 1
            color: MColors.border
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    function formatDate(date) {
        if (!date)
            return "";

        var now = new Date();
        var msgDate = new Date(date);

        if (msgDate.toDateString() === now.toDateString()) {
            return "Today";
        }

        var yesterday = new Date(now);
        yesterday.setDate(yesterday.getDate() - 1);
        if (msgDate.toDateString() === yesterday.toDateString()) {
            return "Yesterday";
        }

        var diffDays = Math.floor((now - msgDate) / (1000 * 60 * 60 * 24));
        if (diffDays < 7) {
            var days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
            return days[msgDate.getDay()];
        }

        return msgDate.toLocaleDateString(Qt.locale(), "MMMM d, yyyy");
    }
}
