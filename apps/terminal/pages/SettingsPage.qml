pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: page

    property var app
    readonly property var schemes: ["ambience", "dark", "light"]

    // Columns the terminal fits at a text size; monospace advance scales with size.
    function columnsAt(size) {
        return Math.floor((width - 2 * Theme.paddingMedium) / (size * metrics.advanceWidth("M") / metrics.font.pixelSize));
    }

    FontMetrics {
        id: metrics

        font.family: "monospace"
        font.pixelSize: 100
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Settings")
            }

            SectionHeader {
                text: qsTr("Text")
            }

            Slider {
                objectName: "fontSizeSlider"
                width: parent.width
                label: qsTr("Text size")
                minimumValue: page.app.minFontSize
                maximumValue: page.app.maxFontSize
                stepSize: 1
                value: page.app.fontSize.value
                valueText: qsTr("%n columns", "", page.columnsAt(Math.round(value)))
                onValueChanged: {
                    if (Math.round(value) !== page.app.fontSize.value)
                        page.app.fontSize.value = Math.round(value);
                }
            }

            ComboBox {
                objectName: "colorSchemeBox"
                label: qsTr("Colours")
                currentIndex: Math.max(0, page.schemes.indexOf(page.app.colorScheme.value))
                onCurrentIndexChanged: page.app.colorScheme.value = page.schemes[currentIndex]
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Ambience")
                    }
                    MenuItem {
                        text: qsTr("Light on black")
                    }
                    MenuItem {
                        text: qsTr("Dark on white")
                    }
                }
            }

            SectionHeader {
                text: qsTr("Keyboard")
            }

            TextSwitch {
                objectName: "extraKeysSwitch"
                text: qsTr("Extra keys")
                description: qsTr("Show Esc, Tab, Ctrl, Alt and arrow keys below the terminal")
                checked: page.app.extraKeys.value
                onCheckedChanged: page.app.extraKeys.value = checked
            }
        }

        VerticalScrollDecorator {}
    }
}
