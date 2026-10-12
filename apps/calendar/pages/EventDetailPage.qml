import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls // qmllint disable unused-imports
// ^ required at runtime for the StackView attached property (root.StackView.view);
//   qmllint does not count attached-property use, so it reports it unused.
import QtQuick.Layouts

MPage {
    id: root

    property var event: ({})
    property var deleteCallback: null
    readonly property int backLayers: deleteDialog.showing ? 1 : 0

    function handleBack() {
        deleteDialog.hide();
    }

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
                    text: Qt.formatDate(Date.fromLocaleString(Qt.locale(), root.event.date, "yyyy-MM-dd"), "MMMM d, yyyy")
                    color: MColors.text
                    font.pixelSize: MTypography.sizeBody
                }

                Text {
                    text: root.event.allDay ? "All Day" : root.event.time
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeSmall
                }
            }
        }

        MButton {
            Layout.fillWidth: true
            Layout.margins: MSpacing.lg
            Layout.topMargin: MSpacing.xl
            text: "Delete Event"
            variant: "danger"
            onClicked: deleteDialog.show()
        }

        Item {
            Layout.fillHeight: true
        }
    }

    MConfirmDialog {
        id: deleteDialog

        title: "Delete this event?"
        message: "\"" + (root.event.title || "Untitled Event") + "\" will be removed from your calendar."
        confirmText: "Delete event"
        cancelText: "Keep"
        destructive: true
        onCancelled: hide()
        onConfirmed: {
            root.deleteCallback(root.event.id);  // qmllint disable use-proper-function
            root.StackView.view.pop();
        }
    }
}
