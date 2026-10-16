import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "MediaPlayback"
    when: windowShown

    Window {
        width: 720
        height: 400
        visible: true

        MediaPlaybackManager {
            id: media
        }
    }

    function init() {
        MPRIS2Controller.hasActivePlayer = true;
        MPRIS2Controller.playerName = "Shortwave";
        MPRIS2Controller.trackTitle = "";
        MPRIS2Controller.trackArtist = "";
        MPRIS2Controller.albumArtUrl = "";
        MPRIS2Controller.trackLength = 0;
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

    function test_missingArtShowsInitials() {
        MPRIS2Controller.trackArtist = "CJME News/Talk 980 (Regina, SK)";
        compare(media.initials, "CN");
        verify(findChild(media, "initialsTile").visible);
    }

    function test_artHidesInitials() {
        MPRIS2Controller.trackArtist = "CJME News/Talk 980 (Regina, SK)";
        MPRIS2Controller.albumArtUrl = "file:///tmp/cover.png";
        verify(!findChild(media, "initialsTile").visible);
    }

    function test_liveStreamHasNoProgress() {
        verify(!findChild(media, "progressRow").visible);
        MPRIS2Controller.trackLength = 180e6;
        verify(findChild(media, "progressRow").visible);
    }
}
