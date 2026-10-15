import QtQuick
import Sailfish.Silica as S

// The lead of a cover that answers with one value: a count, a time, a
// distance, large in the highlight colour, with what it counts beneath.
Column {
    id: root

    property alias value: valueLabel.text
    property alias label: captionLabel.text
    property alias valueColor: valueLabel.color

    S.Label {
        id: valueLabel

        objectName: "coverValue"
        width: root.width
        visible: text !== ""
        color: S.Theme.highlightColor
        font.pixelSize: S.Theme.fontSizeHuge
        font.weight: Font.Light
        font.features: ({ "tnum": 1 })
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: S.Theme.fontSizeLarge
    }
    S.Label {
        id: captionLabel

        objectName: "coverLabel"
        width: root.width
        visible: text !== ""
        font.pixelSize: S.Theme.fontSizeSmall
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
    }
}
