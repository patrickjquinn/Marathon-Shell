import QtQuick
import Sailfish.Silica 1.0

// A station's logo, or its initials on a tile when it has none (many
// stations' logos are missing, tiny or gone).
Rectangle {
    id: art

    property var station: null
    readonly property string _name: station ? station.name : ""
    readonly property string _logo: station && station.favicon && station.favicon.indexOf("http") === 0 ? station.favicon : ""

    // A station's mark: a short code in its name ("R1", "2FM", "104"),
    // else the first letters of its first two telling words.
    function _initials(name) {
        const words = name.replace(/[^\p{L}\p{N} ]/gu, " ").split(" ").filter(w => w.length > 0 && !/^(the|radio|fm)$/i.test(w));
        const code = words.find(w => /\d/.test(w) && w.length <= 3);
        if (code)
            return code.toUpperCase();
        if (words.length === 0)
            return name.substring(0, 2).toUpperCase();
        return words.slice(0, 2).map(w => w[0]).join("").toUpperCase();
    }

    // A hue of the name, so a station keeps its colour everywhere.
    function _hue(name) {
        let h = 0;
        for (let i = 0; i < name.length; i++)
            h = (h * 31 + name.charCodeAt(i)) % 360;
        return h / 360;
    }

    color: logo.status === Image.Ready ? "#f2f2f2" : Qt.hsla(_hue(_name), 0.32, 0.16, 1)
    radius: Theme.paddingSmall / 2
    clip: true

    Label {
        anchors.centerIn: parent
        visible: logo.status !== Image.Ready
        text: art._initials(art._name)
        font.pixelSize: Math.round(art.height * 0.36)
        font.weight: Font.DemiBold
        color: Qt.hsla(art._hue(art._name), 0.65, 0.72, 1)
    }

    Image {
        id: logo

        anchors.fill: parent
        anchors.margins: Math.round(parent.height * 0.08)
        source: art._logo
        sourceSize.width: 192
        sourceSize.height: 192
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: true
        smooth: true
        visible: status === Image.Ready
    }
}
