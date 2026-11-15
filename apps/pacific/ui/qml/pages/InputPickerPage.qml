// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A page's date, time or colour field, with Silica's pickers.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: dialog

    property string type
    property string value
    property var view
    property bool _answered: false

    allowedOrientations: Orientation.All

    function pad(n: var): var { return (n < 10 ? "0" : "") + n }

    onAccepted: {
        _answered = true
        var d = date.date
        var out = ""
        if (type === "date")
            out = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
        else if (type === "month")
            out = d.getFullYear() + "-" + pad(d.getMonth() + 1)
        else if (type === "time")
            out = pad(time.hour) + ":" + pad(time.minute)
        else if (type === "datetime-local")
            out = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + "T" + pad(time.hour) + ":" + pad(time.minute)
        else if (type === "color")
            out = colorText.text
        else
            out = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
        view.resolveInputPicker(out)
    }
    onRejected: if (!_answered && view) view.cancelInputPicker()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            DialogHeader { title: dialog.type === "time" ? qsTr("Time") : (dialog.type === "color" ? qsTr("Colour") : qsTr("Date")) }
            DatePicker {
                id: date
                visible: dialog.type !== "time" && dialog.type !== "color"
                date: dialog.value !== "" && !isNaN(Date.parse(dialog.value)) ? new Date(dialog.value) : new Date()
            }
            TimePicker {
                id: time
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dialog.type === "time" || dialog.type === "datetime-local"
            }
            TextField {
                id: colorText
                width: parent.width
                visible: dialog.type === "color"
                label: qsTr("Colour, as #rrggbb")
                placeholderText: "#rrggbb"
                text: dialog.value
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
        VerticalScrollDecorator {}
    }
}
