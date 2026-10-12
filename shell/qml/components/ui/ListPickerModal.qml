pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica

Modal {
    id: listPickerModal

    property var options: []
    property int selectedIndex: 0

    signal selected(int index, string value)

    Column {
        width: parent.width
        spacing: 0

        Repeater {
            model: listPickerModal.options

            Silica.BackgroundItem {
                id: optionRow

                required property int index
                required property var modelData

                readonly property bool isCurrent: index === listPickerModal.selectedIndex

                width: parent.width
                height: Silica.Theme.itemSizeSmall
                onClicked: {
                    listPickerModal.selectedIndex = optionRow.index;
                    listPickerModal.selected(optionRow.index, optionRow.modelData);
                    listPickerModal.close();
                }

                Silica.Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Silica.Theme.paddingMedium
                    anchors.rightMargin: Silica.Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    text: optionRow.modelData
                    color: (optionRow.highlighted || optionRow.isCurrent) ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                    truncationMode: Silica.TruncationMode.Fade
                }
            }
        }
    }
}
