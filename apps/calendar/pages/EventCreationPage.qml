import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

MPage {
    id: root

    property var saveCallback: null
    property date initialDate: new Date()
    property bool showErrors: false
    property bool saveFailed: false
    readonly property bool dirty: titleField.text.trim() !== ""
    readonly property int backLayers: dirty || discardDialog.showing ? 1 : 0

    function handleBack() {
        if (discardDialog.showing)
            discardDialog.hide();
        else
            discardDialog.show();
    }

    function nextHour() {
        const d = new Date();
        d.setHours(d.getHours() + 1, 0, 0, 0);
        return d;
    }

    function save() {
        if (titleField.text.trim() === "") {
            showErrors = true;
            titleField.forceActiveFocus();
            return;
        }
        const saveCallback = root.saveCallback;
        saveFailed = !saveCallback({
            "title": titleField.text.trim(),
            "date": Qt.formatDate(datePicker.selectedDate, "yyyy-MM-dd"),
            "time": Qt.formatTime(timePicker.selectedDate, "HH:mm"),
            "allDay": allDayToggle.checked,
            "recurring": "none"
        });
        if (!saveFailed)
            root.StackView.view.pop();
    }

    title: "New Event"
    showBackButton: true
    onBackClicked: dirty ? discardDialog.show() : root.StackView.view.pop()

    content: ColumnLayout {
        width: parent.width
        spacing: MSpacing.lg

        MFormField {
            Layout.fillWidth: true
            Layout.topMargin: MSpacing.lg
            Layout.leftMargin: MSpacing.lg
            Layout.rightMargin: MSpacing.lg
            label: "Event Title"
            required: true
            errorText: root.showErrors && titleField.text.trim() === "" ? "Add a title to save this event." : ""

            content: TextField {
                id: titleField

                width: parent.width
                placeholderText: "Enter event title"
                placeholderTextColor: MColors.textTertiary
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.text
                padding: MSpacing.md
                onAccepted: root.save()

                background: Rectangle {
                    color: MColors.surface
                    border.color: root.showErrors && titleField.text.trim() === "" ? MColors.error : MColors.border
                    border.width: 1
                    radius: Constants.borderRadiusSmall
                }
            }
        }

        MFormField {
            Layout.fillWidth: true
            Layout.leftMargin: MSpacing.lg
            Layout.rightMargin: MSpacing.lg
            label: "Date"

            content: MDateTimePicker {
                id: datePicker

                width: parent.width
                mode: "date"
                label: "Event date"
                selectedDate: root.initialDate
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: MSpacing.lg
            Layout.rightMargin: MSpacing.lg

            Text {
                text: "All Day"
                color: MColors.text
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                Layout.fillWidth: true
            }

            MToggle {
                id: allDayToggle

                a11yName: "All day"
            }
        }

        MFormField {
            Layout.fillWidth: true
            Layout.leftMargin: MSpacing.lg
            Layout.rightMargin: MSpacing.lg
            visible: !allDayToggle.checked
            label: "Time"

            content: MDateTimePicker {
                id: timePicker

                width: parent.width
                mode: "time"
                label: "Event time"
                selectedDate: root.nextHour()
            }
        }

        MButton {
            Layout.fillWidth: true
            Layout.leftMargin: MSpacing.lg
            Layout.rightMargin: MSpacing.lg
            text: root.saveFailed ? "Try Again" : "Save Event"
            variant: "primary"
            onClicked: root.save()
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: MSpacing.lg
            Layout.rightMargin: MSpacing.lg
            visible: root.saveFailed
            text: "Couldn't save this event because the calendar service isn't responding. Try again in a moment."
            color: MColors.error
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
            wrapMode: Text.WordWrap
        }
    }

    MConfirmDialog {
        id: discardDialog

        title: "Discard this event?"
        message: "The event you started won't be saved."
        confirmText: "Discard"
        cancelText: "Keep editing"
        destructive: true
        onCancelled: hide()
        onConfirmed: root.StackView.view.pop()
    }
}
