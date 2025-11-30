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
    property string placeholder: "Select an option..."
    property bool disabled: false
    property bool expanded: false
    property int maxVisibleItems: 6

    signal selectionChanged(variant value, int index)

    implicitWidth: parent ? parent.width : 240
    implicitHeight: MSpacing.touchTargetMin

    Accessible.role: Accessible.ComboBox
    Accessible.name: label !== "" ? label : placeholder
    Accessible.description: selectedText
    Accessible.editable: false
    Accessible.onPressAction: if (!disabled)
        toggle()

    Keys.onSpacePressed: if (!disabled)
        toggle()
    Keys.onReturnPressed: if (!disabled)
        toggle()
    Keys.onUpPressed: if (expanded)
        selectPrevious()
    Keys.onDownPressed: if (expanded)
        selectNext()
    Keys.onEscapePressed: if (expanded)
        collapse()

    focus: true

    function toggle() {
        if (!disabled) {
            expanded = !expanded;
            MHaptics.lightImpact();
        }
    }

    function collapse() {
        expanded = false;
    }

    function expand() {
        if (!disabled) {
            expanded = true;
        }
    }

    function selectPrevious() {
        if (selectedIndex > 0) {
            selectByIndex(selectedIndex - 1);
        }
    }

    function selectNext() {
        if (selectedIndex < options.length - 1) {
            selectByIndex(selectedIndex + 1);
        }
    }

    function selectByIndex(index) {
        if (index >= 0 && index < options.length) {
            var option = options[index];
            selectedIndex = index;
            selectedValue = typeof option === "object" ? option.value : option;
            selectedText = typeof option === "object" ? option.text : option;
            selectionChanged(selectedValue, index);
            collapse();
            MHaptics.selectionChanged();
        }
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
            id: dropdownButton
            width: parent.width
            height: MSpacing.touchTargetMin
            radius: MRadius.md
            color: {
                if (root.disabled)
                    return MColors.bb10Surface;
                if (mouseArea.pressed)
                    return MColors.highlightSubtle;
                return MColors.bb10Elevated;
            }
            border.width: 1
            border.color: root.expanded ? MColors.marathonTeal : MColors.borderGlass

            scale: mouseArea.pressed ? 0.98 : 1.0

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.sm
                }
            }

            Behavior on border.color {
                ColorAnimation {
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

            Row {
                anchors.fill: parent
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                spacing: MSpacing.sm

                Text {
                    text: root.selectedText !== "" ? root.selectedText : root.placeholder
                    color: root.selectedText !== "" ? MColors.textPrimary : MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    font.weight: MTypography.weightNormal
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - chevronIcon.width - parent.spacing
                    elide: Text.ElideRight
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

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                enabled: !root.disabled
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                onClicked: root.toggle()
            }
        }
    }

    Rectangle {
        id: dropdownMenu
        visible: root.expanded
        y: dropdownButton.y + dropdownButton.height + MSpacing.xs
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

            model: root.options

            delegate: Rectangle {
                required property var modelData
                required property int index

                width: listView.width
                height: 44
                color: {
                    if (index === root.selectedIndex)
                        return MColors.highlightMedium;
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
                    anchors.right: checkIcon.left
                    anchors.rightMargin: MSpacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    text: typeof modelData === "object" ? modelData.text : modelData
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    font.weight: index === root.selectedIndex ? MTypography.weightMedium : MTypography.weightNormal
                    elide: Text.ElideRight
                }

                Icon {
                    id: checkIcon
                    anchors.right: parent.right
                    anchors.rightMargin: MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check"
                    size: 16
                    color: MColors.marathonTeal
                    visible: index === root.selectedIndex
                }

                MouseArea {
                    id: itemMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onClicked: root.selectByIndex(index)
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
