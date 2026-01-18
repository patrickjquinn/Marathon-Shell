import MarathonApp.Calendar
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

MPage {
    id: root

    property var event: ({})
    property var onDelete: null

    title: "Event Details"
    showBackButton: true
    onBackClicked: root.StackView.view.pop()

    content: ColumnLayout {
        width: parent.width
        spacing: MSpacing.lg

        Text {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            text: root.event.title || "Untitled Event"
            color: MColors.text
            font.pixelSize: MTypography.sizeXLarge
            font.weight: Font.Bold
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            spacing: MSpacing.md

            Icon {
                name: "clock"
                size: 24
                color: MColors.textSecondary
            }

            Column {
                Text {
                    text: root.event.allDay ? Qt.formatDate(new Date(root.event.date), "MMMM d, yyyy") : Qt.formatDate(new Date(root.event.date), "MMMM d, yyyy")
                    color: MColors.text
                    font.pixelSize: MTypography.sizeBody
                }

                Text {
                    text: root.event.allDay ? "All Day" : root.event.time
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeSmall
                    visible: !root.event.allDay || true
                }
            }
        }

        MButton {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            Layout.topMargin: MSpacing.xl
            text: "Delete Event"
            variant: "secondary"
            onClicked: {
                if (root.onDelete)
                    root.onDelete(root.event.id);

                root.StackView.view.pop();
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
