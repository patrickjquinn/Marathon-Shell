import QtQuick
import QtQuick.Effects
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Effects

Item {
    id: root

    property string label: ""
    property variant options: []
    property int selectedIndex: -1
    property variant selectedValue: undefined
    property string selectedText: ""
    property string placeholder: "Type to search..."
    property bool disabled: false
    property bool expanded: false
    property int maxVisibleItems: 6
    property bool allowCustomValue: true

    signal selectionChanged(variant value, int index)
    signal textChanged(string text)

    implicitWidth: parent ? parent.width : 240
    implicitHeight: MSpacing.touchTargetMin

    Accessible.role: Accessible.ComboBox
    Accessible.name: label !== "" ? label : placeholder
    Accessible.description: selectedText
    Accessible.editable: true

    focus: true

    function collapse() {
        expanded = false;
    }

    function expand() {
        if (!disabled) {
            expanded = true;
        }
    }

    function selectByIndex(index) {
        if (index >= 0 && index < filteredOptions.length) {
            var option = filteredOptions[index];
            selectedIndex = index;
            selectedValue = typeof option === "object" ? option.value : option;
            selectedText = typeof option === "object" ? option.text : option;
            textInput.text = selectedText;
            selectionChanged(selectedValue, index);
            collapse();
            MHaptics.selectionChanged();
        }
    }

    property var filteredOptions: {
        if (textInput.text === "")
            return options;
        return options.filter(function (option) {
            var text = typeof option === "object" ? option.text : option;
            return text.toLowerCase().includes(textInput.text.toLowerCase());
        });
    }

    Column {
        anchors.fill: parent
        spacing: MSpacing.xs

        Text {
            text: root.label
            color: MColors.textSecondary
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
            font.weight: MTypography.weightMedium
            visible: root.label !== ""
        }

        Rectangle {
            id: inputContainer
            width: parent.width
            height: MSpacing.touchTargetMin
            radius: MRadius.md
            color: root.disabled ? MColors.bb10Surface : MColors.bb10Elevated
            border.width: 1
            border.color: textInput.activeFocus ? MColors.marathonTeal : MColors.borderGlass

            Behavior on border.color {
                ColorAnimation {
                    duration: MMotion.sm
                }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                spacing: MSpacing.sm

                TextInput {
                    id: textInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - chevronIcon.width - parent.spacing
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    font.weight: MTypography.weightNormal
                    clip: true
                    enabled: !root.disabled

                    Text {
                        anchors.fill: parent
                        text: root.placeholder
                        color: MColors.textSecondary
                        font: textInput.font
                        visible: textInput.text === "" && !textInput.activeFocus
                    }

                    onTextChanged: {
                        root.textChanged(text);
                        if (text !== "") {
                            root.expand();
                        }
                    }

                    onActiveFocusChanged: {
                        if (activeFocus) {
                            root.expand();
                        }
                    }

                    Keys.onDownPressed: {
                        if (root.expanded && filteredOptions.length > 0) {
                            listView.currentIndex = 0;
                            listView.forceActiveFocus();
                        }
                    }

                    Keys.onEscapePressed: root.collapse()
                }

                Icon {
                    id: chevronIcon
                    name: "chevron-down"
                    size: 18
                    color: MColors.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: root.expanded ? 180 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: MMotion.sm
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: dropdownMenu
        visible: root.expanded && filteredOptions.length > 0
        y: inputContainer.y + inputContainer.height + MSpacing.xs
        width: parent.width
        height: Math.min(listView.contentHeight, root.maxVisibleItems * 44)
        radius: MRadius.md
        color: MColors.bb10Elevated
        border.width: 1
        border.color: MColors.borderGlass
        z: 1000

        opacity: root.expanded ? 1 : 0
        scale: root.expanded ? 1 : 0.95

        Behavior on opacity {
            NumberAnimation {
                duration: MMotion.sm
            }
        }

        Behavior on scale {
            SpringAnimation {
                spring: MMotion.springMedium
                damping: MMotion.dampingMedium
                epsilon: MMotion.epsilon
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.6)
            shadowVerticalOffset: 4
            shadowBlur: 0.6
            blurMax: 16
            paddingRect: Qt.rect(0, 0, 0, 20)
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: MColors.highlightSubtle
        }

        ListView {
            id: listView
            anchors.fill: parent
            anchors.margins: 2
            clip: true
            currentIndex: -1

            model: root.filteredOptions

            Keys.onUpPressed: {
                if (currentIndex === 0) {
                    textInput.forceActiveFocus();
                } else {
                    decrementCurrentIndex();
                }
            }

            Keys.onDownPressed: incrementCurrentIndex()
            Keys.onReturnPressed: root.selectByIndex(currentIndex)
            Keys.onEscapePressed: {
                root.collapse();
                textInput.forceActiveFocus();
            }

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: listView.width
                height: 44
                color: {
                    if (index === listView.currentIndex && listView.activeFocus)
                        return MColors.marathonTealHoverGradient;
                    if (itemMouseArea.containsMouse)
                        return MColors.highlightSubtle;
                    return "transparent";
                }

                Behavior on color {
                    ColorAnimation {
                        duration: MMotion.xs
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: MSpacing.md
                    anchors.right: parent.right
                    anchors.rightMargin: MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    text: typeof modelData === "object" ? modelData.text : modelData
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    font.weight: MTypography.weightNormal
                    elide: Text.ElideRight
                }

                MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: {
                        root.selectByIndex(index);
                        textInput.forceActiveFocus();
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.expanded
        z: 999
        propagateComposedEvents: false

        onClicked: root.collapse()
    }
}
