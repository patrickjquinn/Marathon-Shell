import MarathonUI.Theme
import QtQuick

Item {
    id: root

    property string source: ""
    property int size: 24
    property bool isMask: false // If true, image is used as a mask (not implemented here but kept for API compat)
    property color color: MColors.textPrimary
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
            // The LunaSVG provider takes the path portion of the URL as `id`.
            // Normalize common schemes so we don't accidentally create a new provider name
            // (e.g. "image://lunasvg" + "qrc:/foo.svg" => "image://lunasvgqrc:/foo.svg").
            var svgPath = source;
            if (svgPath.startsWith("file://"))
                svgPath = svgPath.substring("file://".length);
            // absolute filesystem path
            if (svgPath.startsWith("qrc:/"))
                svgPath = svgPath.substring("qrc:".length);
            // qrc:/foo.svg -> /foo.svg
            if (svgPath.startsWith(":/"))
                svgPath = svgPath.substring(1);
            // :/foo.svg -> /foo.svg
            // Ensure there is a '/' between provider name and path.
            if (!svgPath.startsWith("/"))
                svgPath = "/" + svgPath;

            return "image://lunasvg" + svgPath;
        }
        // For non-SVG files (PNG, etc.), ensure we have proper file:// prefix
        // for absolute filesystem paths, otherwise Qt interprets them relative to qrc
        if (source.startsWith("/") && !source.startsWith("file://"))
            return "file://" + source;

        return source;
    }

    width: size
    height: size

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
