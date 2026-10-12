pragma ComponentBehavior: Bound
import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Rectangle {
    id: dialog

    property string editingAlarmId: ""
    property bool isEditMode: false
    property var repeatDays: []
    readonly property bool showing: visible

    signal alarmCreated(int hour, int minute, string label, var repeat)
    signal alarmUpdated(string alarmId, int hour, int minute, string label, var repeat)
    signal alarmDeleted(string alarmId)

    function open() {
        isEditMode = false;
        editingAlarmId = "";
        const now = new Date();
        hourTumbler.currentIndex = now.getHours();
        minuteTumbler.currentIndex = now.getMinutes();
        labelField.text = "";
        repeatDays = [];
        dialog.visible = true;
    }

    function openForEdit(alarmId, hour, minute, label, repeat) {
        isEditMode = true;
        editingAlarmId = alarmId;
        hourTumbler.currentIndex = hour;
        minuteTumbler.currentIndex = minute;
        labelField.text = label === "Alarm" ? "" : label;
        repeatDays = repeat ? repeat.slice() : [];
        dialog.visible = true;
    }

    function close() {
        dialog.visible = false;
    }

    function toggleDay(day) {
        const days = repeatDays.slice();
        const i = days.indexOf(day);
        if (i === -1)
            days.push(day);
        else
            days.splice(i, 1);
        repeatDays = days.sort();
    }

    anchors.fill: parent
    color: MColors.overlay
    visible: false
    z: Constants.zIndexModalOverlay

    MouseArea {
        anchors.fill: parent
        onClicked: dialog.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - MSpacing.lg * 2, Math.round(400 * Constants.scaleFactor))
        height: Math.min(parent.height - MSpacing.lg * 2, editorColumn.implicitHeight + MSpacing.lg * 2)
        color: MColors.elevated
        radius: MRadius.lg
        border.width: Constants.borderWidthThin
        border.color: MColors.border

        MouseArea {
            anchors.fill: parent
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: MSpacing.lg
            contentHeight: editorColumn.implicitHeight
            clip: true

            Column {
                id: editorColumn

                width: parent.width
                spacing: MSpacing.md

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: dialog.isEditMode ? "Edit Alarm" : "New Alarm"
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.Bold
                    font.family: MTypography.fontFamily
                    color: MColors.text
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: MSpacing.md

                    Tumbler {
                        id: hourTumbler

                        width: Math.round(90 * Constants.scaleFactor)
                        height: Math.round(160 * Constants.scaleFactor)
                        model: 24
                        Accessible.name: "Hour"

                        delegate: Text {
                            required property int modelData

                            text: (modelData < 10 ? "0" : "") + modelData
                            font.pixelSize: MTypography.sizeLarge
                            font.family: MTypography.fontFamily
                            color: MColors.text
                            opacity: Tumbler.tumbler ? 1 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ":"
                        font.pixelSize: MTypography.sizeXLarge
                        font.weight: Font.Bold
                        color: MColors.text
                    }

                    Tumbler {
                        id: minuteTumbler

                        width: Math.round(90 * Constants.scaleFactor)
                        height: Math.round(160 * Constants.scaleFactor)
                        model: 60
                        Accessible.name: "Minute"

                        delegate: Text {
                            required property int modelData

                            text: (modelData < 10 ? "0" : "") + modelData
                            font.pixelSize: MTypography.sizeLarge
                            font.family: MTypography.fontFamily
                            color: MColors.text
                            opacity: Tumbler.tumbler ? 1 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                MTextField {
                    id: labelField

                    width: parent.width
                    label: "Label"
                    placeholder: "Alarm"
                }

                Text {
                    text: "Repeat"
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                }

                Row {
                    id: dayRow

                    width: parent.width
                    spacing: MSpacing.xs

                    Repeater {
                        // Backend day numbers: 0 = Sunday … 6 = Saturday; shown Monday-first.
                        model: [1, 2, 3, 4, 5, 6, 0]

                        Rectangle {
                            id: dayChip

                            required property int modelData
                            readonly property bool selected: dialog.repeatDays.indexOf(modelData) !== -1

                            width: (dayRow.width - dayRow.spacing * 6) / 7
                            height: Math.max(MSpacing.touchTargetMin, width)
                            radius: width / 2
                            color: selected ? MColors.accent : MColors.surface
                            border.width: 1
                            border.color: selected ? MColors.accent : MColors.border

                            Accessible.role: Accessible.CheckBox
                            Accessible.name: Qt.locale().dayName(modelData)
                            Accessible.checkable: true
                            Accessible.checked: selected
                            Accessible.onToggleAction: dialog.toggleDay(modelData)
                            Accessible.onPressAction: dialog.toggleDay(modelData)

                            Text {
                                anchors.centerIn: parent
                                text: Qt.locale().dayName(dayChip.modelData, Locale.NarrowFormat)
                                color: dayChip.selected ? MColors.textOnAccent : MColors.text
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    dialog.toggleDay(dayChip.modelData);
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: MSpacing.md

                    MButton {
                        text: "Cancel"
                        variant: "secondary"
                        onClicked: {
                            HapticService.light();
                            dialog.close();
                        }
                    }

                    MButton {
                        text: "Save"
                        variant: "primary"
                        onClicked: {
                            HapticService.light();
                            const label = labelField.text.trim();
                            if (dialog.isEditMode)
                                dialog.alarmUpdated(dialog.editingAlarmId, hourTumbler.currentIndex, minuteTumbler.currentIndex, label, dialog.repeatDays);
                            else
                                dialog.alarmCreated(hourTumbler.currentIndex, minuteTumbler.currentIndex, label, dialog.repeatDays);
                            dialog.close();
                        }
                    }
                }

                MButton {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: dialog.isEditMode
                    text: "Delete Alarm"
                    variant: "danger"
                    onClicked: {
                        HapticService.medium();
                        dialog.alarmDeleted(dialog.editingAlarmId);
                        dialog.close();
                    }
                }
            }
        }
    }
}
