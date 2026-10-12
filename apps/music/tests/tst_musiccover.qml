import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    name: "MusicCover"
    when: windowShown
    visible: true
    width: 540; height: 960

    readonly property var track: ({ title: "Teardrop", artist: "Massive Attack" })

    Component { id: cover; MusicCover {} }
    SignalSpy { id: toggleSpy; signalName: "toggleRequested" }
    SignalSpy { id: nextSpy; signalName: "nextRequested" }

    function test_placeholderWithoutTrack() {
        const c = createTemporaryObject(cover, this);
        verify(findChild(c, "coverPlaceholder").visible);
        verify(!findChild(c, "coverTrack").visible);
    }

    function test_showsTrack() {
        const c = createTemporaryObject(cover, this, { track: track });
        verify(!findChild(c, "coverPlaceholder").visible);
        compare(findChild(c, "coverTitle").text, "Teardrop");
    }

    function test_playPauseIcon() {
        const c = createTemporaryObject(cover, this, { track: track, playing: false });
        const action = findChild(c, "coverPlayPause");
        compare(String(action.iconSource), "image://theme/icon-cover-play");
        c.playing = true;
        compare(String(action.iconSource), "image://theme/icon-cover-pause");
    }

    function test_actions() {
        const c = createTemporaryObject(cover, this, { track: track });
        toggleSpy.target = c;
        nextSpy.target = c;
        toggleSpy.clear();
        nextSpy.clear();
        findChild(c, "coverPlayPause").triggered();
        findChild(c, "coverNext").triggered();
        compare(toggleSpy.count, 1);
        compare(nextSpy.count, 1);
    }

    function test_progressFollowsOnlyWhileActive() {
        const c = createTemporaryObject(cover, this, { track: track, progress: 0.5 });
        const bar = findChild(c, "coverProgress");
        compare(bar.width, 0, "not drawn while the cover is off screen");
        c._status = Cover.Active;
        verify(bar.width > 0);
        const shown = bar.width;
        c._status = Cover.Inactive;
        c.progress = 0.9;
        compare(bar.width, shown, "frozen while off screen");
    }
}
