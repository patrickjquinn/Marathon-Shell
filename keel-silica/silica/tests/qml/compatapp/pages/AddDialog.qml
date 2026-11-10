// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sample app in the style of Harbour apps (SDK template layout), used by
// tst_compat_app.qml. Written for Keel; no third-party code.
import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog
    objectName: "addDialog"

    property string noteTitle: titleField.text
    property string priority: priorityBox.value
    property bool pinned: pinSwitch.checked
    property alias titleField: titleField
    property alias priorityBox: priorityBox
    property alias pinSwitch: pinSwitch

    canAccept: titleField.text.length > 0

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: qsTr("New note")
        }
        TextField {
            id: titleField
            width: parent.width
            placeholderText: qsTr("Title")
            label: qsTr("Title")
            EnterKey.enabled: text.length > 0
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
        ComboBox {
            id: priorityBox
            label: qsTr("Priority")
            currentIndex: 1
            menu: ContextMenu {
                MenuItem { text: "low" }
                MenuItem { text: "normal" }
                MenuItem { text: "high" }
            }
        }
        TextSwitch {
            id: pinSwitch
            text: qsTr("Pin")
            description: qsTr("Keep at the top")
        }
        Slider {
            width: parent.width
            minimumValue: 1; maximumValue: 5; stepSize: 1; value: 3
            valueText: value
            label: qsTr("Importance")
        }
    }
}
