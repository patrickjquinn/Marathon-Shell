pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property date selectedDate: new Date()
    property string mode: "date"
    property string label: ""

    signal dateSelected(date date)

    implicitWidth: Math.round(200 * scaleFactor)
    implicitHeight: MSpacing.touchTargetMin

    Accessible.role: Accessible.Button
    Accessible.name: label !== "" ? label : (mode === "time" ? qsTr("Select time") : qsTr("Select date"))
    Accessible.description: Qt.formatDateTime(selectedDate, mode === "time" ? "hh:mm" : "yyyy-MM-dd")
    Accessible.onPressAction: pickerSheet.showing = true

    color: MColors.bb10Surface
    radius: MRadius.md
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    MTopHairline {
        radius: parent.radius
        color: Qt.rgba(1, 1, 1, 0.04)
        lineWidth: 1
    }

    MouseArea {
        anchors.fill: parent
        onClicked: pickerSheet.showing = true
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: MSpacing.sm

        Icon {
            name: root.mode === "date" ? "calendar" : "clock"
            size: Math.round(24 * root.scaleFactor)
            color: MColors.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: {
                if (root.mode === "date") {
                    return Qt.formatDate(root.selectedDate, "MMM dd, yyyy");
                } else if (root.mode === "time") {
                    return Qt.formatTime(root.selectedDate, "hh:mm AP");
                } else {
                    return Qt.formatDateTime(root.selectedDate, "MMM dd, yyyy hh:mm AP");
                }
            }
            font.pixelSize: MTypography.sizeBody
            color: MColors.textPrimary
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            width: parent.width - parent.spacing - 24
        }
    }

    MSheet {
        id: pickerSheet
        title: root.label || (root.mode === "date" ? "Select Date" : "Select Time")
        // Reparented to the window so the field's clipping container can't hide it.
        parent: root.Window.window ? root.Window.window.contentItem : root

        content: [
            Column {
                width: parent.width
                spacing: MSpacing.lg

                Row {
                    spacing: MSpacing.sm
                    anchors.horizontalCenter: parent.horizontalCenter

                    Tumbler {
                        id: monthTumbler
                        visible: root.mode !== "time"
                        model: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                        currentIndex: root.selectedDate.getMonth()
                        delegate: Text {
                            required property var modelData

                            text: modelData
                            font.pixelSize: MTypography.sizeLarge
                            color: MColors.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: Tumbler.tumbler ? 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                        }
                    }

                    Tumbler {
                        id: dayTumbler
                        visible: root.mode !== "time"
                        model: 31
                        currentIndex: root.selectedDate.getDate() - 1
                        delegate: Text {
                            required property int modelData

                            text: modelData + 1
                            font.pixelSize: MTypography.sizeLarge
                            color: MColors.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: Tumbler.tumbler ? 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                        }
                    }

                    Tumbler {
                        id: yearTumbler
                        visible: root.mode !== "time"
                        model: 100
                        currentIndex: root.selectedDate.getFullYear() - 1950
                        delegate: Text {
                            required property int modelData

                            text: modelData + 1950
                            font.pixelSize: MTypography.sizeLarge
                            color: MColors.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: Tumbler.tumbler ? 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                        }
                    }

                    Tumbler {
                        id: hourTumbler
                        visible: root.mode !== "date"
                        model: 12
                        currentIndex: root.selectedDate.getHours() % 12
                        delegate: Text {
                            required property int modelData

                            text: modelData === 0 ? 12 : modelData
                            font.pixelSize: MTypography.sizeLarge
                            color: MColors.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: Tumbler.tumbler ? 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                        }
                    }

                    Text {
                        visible: root.mode !== "date"
                        text: ":"
                        font.pixelSize: MTypography.sizeXLarge
                        color: MColors.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Tumbler {
                        id: minuteTumbler
                        visible: root.mode !== "date"
                        model: 60
                        currentIndex: root.selectedDate.getMinutes()
                        delegate: Text {
                            required property int modelData

                            text: modelData < 10 ? "0" + modelData : modelData
                            font.pixelSize: MTypography.sizeLarge
                            color: MColors.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: Tumbler.tumbler ? 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                        }
                    }

                    Tumbler {
                        id: ampmTumbler
                        visible: root.mode !== "date"
                        model: ["AM", "PM"]
                        currentIndex: root.selectedDate.getHours() >= 12 ? 1 : 0
                        delegate: Text {
                            required property var modelData

                            text: modelData
                            font.pixelSize: MTypography.sizeLarge
                            color: MColors.textPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: Tumbler.tumbler ? 1.0 - Math.abs(Tumbler.displacement) / (Tumbler.tumbler.visibleItemCount / 2) : 1
                        }
                    }
                }

                Row {
                    spacing: MSpacing.md
                    anchors.horizontalCenter: parent.horizontalCenter

                    MButton {
                        text: "Cancel"
                        variant: "secondary"
                        onClicked: pickerSheet.showing = false
                    }

                    MButton {
                        text: "Done"
                        variant: "primary"
                        onClicked: {
                            var newDate = new Date(root.selectedDate);

                            if (root.mode !== "time") {
                                var year = yearTumbler.currentIndex + 1950;
                                var month = monthTumbler.currentIndex;
                                var daysInMonth = new Date(year, month + 1, 0).getDate();
                                newDate.setFullYear(year, month, Math.min(dayTumbler.currentIndex + 1, daysInMonth));
                            }

                            if (root.mode !== "date") {
                                newDate.setHours(hourTumbler.currentIndex + (ampmTumbler.currentIndex === 1 ? 12 : 0));
                                newDate.setMinutes(minuteTumbler.currentIndex);
                            }

                            root.selectedDate = newDate;
                            root.dateSelected(newDate);
                            pickerSheet.showing = false;
                        }
                    }
                }
            }
        ]
    }
}
