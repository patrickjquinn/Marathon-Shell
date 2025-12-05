import QtQuick
import MarathonUI.Theme

Item {
    id: root

    property string source: ""
    property int size: 24
    property bool isMask: false // If true, image is used as a mask (not implemented here but kept for API compat)
    property color color: MColors.textPrimary

    width: size
    height: size

    // Logic to determine if source is an image path or an icon name
    readonly property bool isImage: source.indexOf("/") >= 0 || source.indexOf("file:") >= 0 || source.indexOf("qrc:") >= 0

    // 1. Image Handler (for native apps / external paths)
    Image {
        anchors.fill: parent
        source: root.isImage ? root.source : ""
        visible: root.isImage
        sourceSize: Qt.size(root.size, root.size)
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        cache: true
    }

    // 2. Font Icon Handler (for internal apps / Lucide names)
    Icon {
        anchors.centerIn: parent
        name: !root.isImage ? root.source : ""
        size: root.size
        visible: !root.isImage
        color: root.color
    }
}
