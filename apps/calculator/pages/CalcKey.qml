import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

BackgroundItem {
    id: root

    property string key
    property string kind: "digit"

    readonly property var _names: ({
            "C": qsTr("Clear"),
            "⌫": qsTr("Delete"),
            "%": qsTr("Percent"),
            "÷": qsTr("Divide"),
            "×": qsTr("Multiply"),
            "−": qsTr("Minus"),
            "+": qsTr("Plus"),
            "+/−": qsTr("Change sign"),
            ".": qsTr("Decimal point"),
            "=": qsTr("Equals"),
            "mod": qsTr("Modulo"),
            "π": qsTr("Pi"),
            "√": qsTr("Square root"),
            "x²": qsTr("Square"),
            "sin": qsTr("Sine"),
            "cos": qsTr("Cosine"),
            "tan": qsTr("Tangent"),
            "log": qsTr("Logarithm"),
            "ln": qsTr("Natural logarithm"),
            "!": qsTr("Factorial"),
            "ans": qsTr("Last answer")
        })

    objectName: "key_" + key
    Accessible.name: _names[key] || key

    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.paddingSmall
        radius: Theme.paddingSmall
        visible: root.kind === "equals"
        color: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
    }

    Label {
        anchors.centerIn: parent
        visible: root.key !== "⌫"
        text: root.key
        font.pixelSize: root.kind === "function" ? Theme.fontSizeMedium : Theme.fontSizeExtraLarge
        color: root.highlighted || root.kind === "op" || root.kind === "equals" ? Theme.highlightColor
               : root.kind === "soft" || root.kind === "function" ? Theme.secondaryColor : Theme.primaryColor
    }

    Icon {
        anchors.centerIn: parent
        visible: root.key === "⌫"
        source: "image://theme/icon-m-backspace"
        highlighted: root.highlighted
    }
}
