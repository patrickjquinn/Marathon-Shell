import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: timerPage

    property int remainingSeconds: 0
    property bool isRunning: false
    property int totalSeconds: 0
    readonly property bool isIdle: !isRunning && remainingSeconds === 0
    readonly property int quickColumns: width < 360 ? 2 : 3
    readonly property real contentWidth: Math.max(1, width - MSpacing.lg * 2)
    readonly property real quickWidth: Math.min(contentWidth, Math.round((Constants && Constants.screenWidth > 0 ? Constants.screenWidth : width) * 0.85))

    function formatTime(seconds) {
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        var s = seconds % 60;
        if (h > 0)
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
        else
            return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Timer {
        id: countdownTimer

        interval: 1000
        running: timerPage.isRunning
        repeat: true
        onTriggered: {
            if (timerPage.remainingSeconds > 0) {
                timerPage.remainingSeconds--;
            } else {
                timerPage.isRunning = false;
                HapticService.heavy();
            }
        }
    }

    Item {
        anchors.fill: parent

        Text {
            id: timeText

            anchors.top: parent.top
            anchors.topMargin: MSpacing.xl
            anchors.horizontalCenter: parent.horizontalCenter
            text: formatTime(timerPage.remainingSeconds)
            color: MColors.textPrimary
            font.pixelSize: Math.min(MTypography.sizeHuge * 1.8, Math.round(parent.width * 0.22))
            font.weight: Font.Light
        }

        Column {
            id: quickTimers

            anchors.top: timeText.bottom
            anchors.topMargin: MSpacing.lg
            anchors.horizontalCenter: parent.horizontalCenter
            width: timerPage.quickWidth
            spacing: MSpacing.md
            visible: timerPage.isIdle

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Quick Timers"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
            }

            Grid {
                id: quickGrid

                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                columns: timerPage.quickColumns
                columnSpacing: MSpacing.md
                rowSpacing: MSpacing.md

                Repeater {
                    model: [1, 3, 5, 10, 15, 30]

                    MButton {
                        required property int modelData
                        readonly property int cols: timerPage.quickColumns

                        width: Math.floor((quickGrid.width - quickGrid.columnSpacing * (cols - 1)) / cols)
                        text: modelData + " min"
                        variant: "secondary"
                        onClicked: {
                            HapticService.light();
                            remainingSeconds = modelData * 60;
                            totalSeconds = remainingSeconds;
                        }
                    }
                }
            }
        }

        Row {
            id: controlsRow

            anchors.bottom: parent.bottom
            anchors.bottomMargin: MSpacing.xl
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: MSpacing.lg

            MButton {
                text: timerPage.isRunning ? "Pause" : "Start"
                variant: "primary"
                enabled: timerPage.remainingSeconds > 0
                onClicked: {
                    HapticService.light();
                    timerPage.isRunning = !timerPage.isRunning;
                }
            }

            MButton {
                text: "Reset"
                variant: "secondary"
                enabled: timerPage.remainingSeconds > 0 || timerPage.totalSeconds > 0
                onClicked: {
                    HapticService.light();
                    timerPage.isRunning = false;
                    timerPage.remainingSeconds = 0;
                    timerPage.totalSeconds = 0;
                }
            }
        }
    }
}
