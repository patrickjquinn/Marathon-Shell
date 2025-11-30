import QtQuick
import MarathonUI.Theme

Column {
    id: root

    property string groupName: "radioGroup_" + Math.random().toString(36).substr(2, 9)
    property variant selectedValue: undefined
    property int selectedIndex: -1
    property alias options: optionsRepeater.model
    property alias spacing: root.spacing

    signal selectionChanged(variant value, int index)

    spacing: MSpacing.sm

    Accessible.role: Accessible.RadioButton
    Accessible.name: "Radio button group"

    Repeater {
        id: optionsRepeater

        delegate: MRadioButton {
            required property var modelData
            required property int index

            text: typeof modelData === "object" ? modelData.text : modelData
            value: typeof modelData === "object" ? modelData.value : modelData
            groupName: root.groupName
            checked: root.selectedIndex === index

            onToggled: function (isChecked) {
                if (isChecked) {
                    root.selectedValue = value;
                    root.selectedIndex = index;
                    root.selectionChanged(value, index);
                }
            }
        }
    }

    function selectByIndex(index) {
        if (index >= 0 && index < optionsRepeater.count) {
            var item = optionsRepeater.itemAt(index);
            if (item) {
                item.select();
            }
        }
    }

    function selectByValue(value) {
        for (var i = 0; i < optionsRepeater.count; i++) {
            var item = optionsRepeater.itemAt(i);
            if (item && item.value === value) {
                item.select();
                return;
            }
        }
    }
}
