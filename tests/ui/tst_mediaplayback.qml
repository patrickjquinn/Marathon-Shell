import QtQuick
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "MediaPlayback"

    MediaPlaybackManager {
        id: media
    }

    function init() {
        MPRIS2Controller.hasActivePlayer = true;
        MPRIS2Controller.playerName = "Shortwave";
        MPRIS2Controller.trackTitle = "";
        MPRIS2Controller.trackArtist = "";
    }

    function test_trackShowsTitleAndArtist() {
        MPRIS2Controller.trackTitle = "Song";
        MPRIS2Controller.trackArtist = "Band";
        compare(media.trackTitle, "Song");
        compare(media.artist, "Band");
    }

    function test_streamWithoutTitleShowsStation() {
        MPRIS2Controller.trackArtist = "CJME News/Talk 980";
        compare(media.trackTitle, "CJME News/Talk 980");
        compare(media.artist, "Shortwave");
    }

    function test_noMetadataShowsPlayer() {
        compare(media.trackTitle, "Shortwave");
    }
}
