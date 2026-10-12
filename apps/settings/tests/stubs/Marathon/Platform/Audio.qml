pragma Singleton
import QtQml
import QtQml.Models

QtObject {
    property real volume: 0.4
    property bool muted: false
    property bool perAppVolumeSupported: true
    property bool doNotDisturb: false
    property var previewed: []
    property ListModel streams: ListModel {}

    function reset() {
        volume = 0.4;
        muted = false;
        perAppVolumeSupported = true;
        doNotDisturb = false;
        previewed = [];
        streams.clear();
    }
    function setVolume(v) {
        volume = v;
    }
    function setMuted(on) {
        muted = on;
    }
    function setDoNotDisturb(on) {
        doNotDisturb = on;
    }
    function setStreamVolume(id, v) {
        for (let i = 0; i < streams.count; i++) {
            if (streams.get(i).streamId === id)
                streams.setProperty(i, "volume", v);
        }
    }
    function setStreamMuted(id, on) {
        for (let i = 0; i < streams.count; i++) {
            if (streams.get(i).streamId === id)
                streams.setProperty(i, "muted", on);
        }
    }
    function previewSound(path) {
        previewed = previewed.concat([path]);
    }
}
