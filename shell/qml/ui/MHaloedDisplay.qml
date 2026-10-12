import QtQuick
import Sailfish.Silica 1.0 as Silica

// Hero numeric (clock) in Sailfish display type.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    property alias text: label.text
    property alias color: label.color
    property alias textFormat: label.textFormat
    property alias horizontalAlignment: label.horizontalAlignment

    // Plain properties, not a font alias: aliasing made Qt drop the weight.
    property int pixelSize: Silica.Theme.fontSizeHuge
    property int weight: Font.Light
    property real letterSpacing: 0

    // Width cap; 0 = unbounded. Text shrinks to fit, down to minimumPixelSize.
    property real maxWidth: 0
    property int minimumPixelSize: Silica.Theme.fontSizeLarge

    Text {
        id: label
        anchors.centerIn: parent
        color: Silica.Theme.primaryColor
        font.family: Silica.Theme.fontFamilyHeading
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        font.letterSpacing: root.letterSpacing
        renderType: Text.NativeRendering

        width: root.maxWidth > 0 ? root.maxWidth : implicitWidth
        horizontalAlignment: Text.AlignHCenter
        fontSizeMode: root.maxWidth > 0 ? Text.HorizontalFit : Text.FixedSize
        minimumPixelSize: root.minimumPixelSize
    }
}
