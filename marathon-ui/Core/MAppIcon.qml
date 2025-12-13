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

    // Check if this is an SVG file that should use LunaSVG
    readonly property bool isSvg: source.endsWith(".svg")

    // Get the actual image source - use lunasvg:// scheme for SVG files
    readonly property string imageSource: {
        if (!isImage)
            return "";

        // For SVG files, use LunaSVG image provider for proper clipPath support
        if (isSvg) {
            // Strip file:// prefix if present, as the provider expects absolute paths
            var svgPath = source.replace("file://", "");
            return "image://lunasvg" + svgPath;
        }

        // For non-SVG files (PNG, etc.), ensure we have proper file:// prefix
        // for absolute filesystem paths, otherwise Qt interprets them relative to qrc
        if (source.startsWith("/") && !source.startsWith("file://")) {
            return "file://" + source;
        }

        return source;
    }

    // 1. Image Handler (for native apps / external paths)
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

    // 2. Font Icon Handler (for internal apps / Lucide names)
    Icon {
        anchors.centerIn: parent
        name: !root.isImage ? root.source : ""
        size: root.size
        visible: !root.isImage
        color: root.color
    }
}
