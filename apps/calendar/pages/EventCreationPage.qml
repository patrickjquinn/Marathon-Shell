import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Navigation

MPage {
    id: root
    title: "New Event"
    showBackButton: true
    onBackClicked: root.StackView.view.pop()

    property var onSave: null

    content: ColumnLayout {
        width: parent.width
        spacing: MSpacing.lg

        // Title Field
        MFormField {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            label: "Event Title"
            required: true

            content: TextField {
                id: titleField
                width: parent.width
                placeholderText: "Enter event title"
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.text
                background: Rectangle {
                    color: MColors.surface
                    border.color: MColors.border
                    border.width: 1
                    radius: Constants.borderRadiusSmall
                }
                padding: MSpacing.md
            }
        }

        // Date Field (Simplified for now, using text input)
        MFormField {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            label: "Date (YYYY-MM-DD)"
            required: true

            content: TextField {
                id: dateField
                width: parent.width
                text: Qt.formatDate(new Date(), "yyyy-MM-dd")
                placeholderText: "YYYY-MM-DD"
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.text
                background: Rectangle {
                    color: MColors.surface
                    border.color: MColors.border
                    border.width: 1
                    radius: Constants.borderRadiusSmall
                }
                padding: MSpacing.md
            }
        }

        // Time Field
        MFormField {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            label: "Time (HH:MM)"

            content: TextField {
                id: timeField
                width: parent.width
                text: Qt.formatTime(new Date(), "HH:mm")
                placeholderText: "HH:MM"
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.text
                background: Rectangle {
                    color: MColors.surface
                    border.color: MColors.border
                    border.width: 1
                    radius: Constants.borderRadiusSmall
                }
                padding: MSpacing.md
            }
        }

        // All Day Toggle
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg

            Text {
                text: "All Day"
                color: MColors.text
                font.pixelSize: MTypography.sizeBody
                Layout.fillWidth: true
            }

            Switch {
                id: allDaySwitch
                checked: false
            }
        }

        // Save Button
        MButton {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            text: "Save Event"
            variant: "primary"
            onClicked: {
                if (titleField.text === "") {
                    // Show error (TODO: proper validation feedback)
                    return;
                }

                var newEvent = {
                    title: titleField.text,
                    date: dateField.text,
                    time: timeField.text,
                    allDay: allDaySwitch.checked,
                    recurring: "none" // Default for now
                };

                if (root.onSave) {
                    root.onSave(newEvent);
                }
                root.StackView.view.pop();
            }
        }

        Item {
            Layout.fillHeight: true
        } // Spacer
    }
}
