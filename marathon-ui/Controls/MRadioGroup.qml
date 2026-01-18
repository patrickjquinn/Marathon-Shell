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
        if (index < 0 || index >= optionsRepeater.count)
            return;

        var data = optionsRepeater.model;
        var entry = data;
        if (data && typeof data.get === "function")
            entry = data.get(index);
        else if (Array.isArray(data))
            entry = data[index];
        else if (data && data.length !== undefined)
            entry = data[index];

        var value = entry;
        if (entry && typeof entry === "object" && entry.value !== undefined)
            value = entry.value;

        root.selectedIndex = index;
        root.selectedValue = value;
        root.selectionChanged(value, index);
    }

    function selectByValue(value) {
        var data = optionsRepeater.model;
        for (var i = 0; i < optionsRepeater.count; i++) {
            var entry = data;
            if (data && typeof data.get === "function")
                entry = data.get(i);
            else if (Array.isArray(data))
                entry = data[i];
            else if (data && data.length !== undefined)
                entry = data[i];

            var entryValue = entry;
            if (entry && typeof entry === "object" && entry.value !== undefined)
                entryValue = entry.value;

            if (entryValue === value) {
                root.selectedIndex = i;
                root.selectedValue = entryValue;
                root.selectionChanged(entryValue, i);
                return;
            }
        }
    }
}
