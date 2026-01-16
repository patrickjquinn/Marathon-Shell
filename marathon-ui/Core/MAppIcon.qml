import MarathonUI.Theme
import QtQuick

Item {
    id: root

    property string source: ""
    property int size: 24
    property bool isMask: false
    property color color: MColors.textPrimary

    readonly property bool isImage: source.indexOf("/") >= 0 || source.indexOf("file:") >= 0 || source.indexOf("qrc:") >= 0

    readonly property bool isSvg: source.endsWith(".svg")
    readonly property int status: imageItem.status

    readonly property string imageSource: {
        if (!isImage)
            return "";

        if (isSvg) {
            var svgPath = source;
            if (svgPath.startsWith("file://"))
                svgPath = svgPath.substring("file://".length);

            if (svgPath.startsWith("qrc:/"))
                svgPath = svgPath.substring("qrc:".length);

            if (svgPath.startsWith(":/"))
                svgPath = svgPath.substring(1);

            if (!svgPath.startsWith("/"))
                svgPath = "/" + svgPath;

            return "image://lunasvg" + svgPath;
        }

        if (source.startsWith("/") && !source.startsWith("file://"))
            return "file://" + source;

        return source;
    }

    width: size
    height: size

    Image {
        id: imageItem

        anchors.fill: parent
        source: root.imageSource
        visible: root.isImage
        sourceSize: Qt.size(root.size, root.size)
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
        cache: true
    }

    Icon {
        anchors.centerIn: parent
        name: !root.isImage ? root.source : ""
        size: root.size
        visible: !root.isImage
        color: root.color
    }
}
