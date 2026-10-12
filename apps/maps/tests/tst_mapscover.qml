import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    id: tc

    name: "MapsCover"
    when: windowShown
    visible: true
    width: 270
    height: 430

    Component {
        id: coverComponent

        MapsCover {
            width: 270
            height: 430
        }
    }

    function test_empty() {
        const cover = createTemporaryObject(coverComponent, tc);
        verify(findChild(cover, "coverPlaceholder").visible);
        verify(!findChild(cover, "coverPlace").visible);
        verify(!findChild(cover, "coverNavigation").visible);
        compare(findChild(cover, "coverAction").iconSource, "image://theme/icon-cover-search");
    }

    function test_place() {
        const cover = createTemporaryObject(coverComponent, tc, { place: { name: "Tower Bridge", address: "London" } });
        verify(!findChild(cover, "coverPlaceholder").visible);
        verify(findChild(cover, "coverPlace").visible);
        compare(findChild(cover, "coverPlaceName").text, "Tower Bridge");
        const spy = createTemporaryQmlObject("import QtTest; SignalSpy { signalName: \"searchRequested\" }", tc);
        spy.target = cover;
        findChild(cover, "coverAction").triggered();
        compare(spy.count, 1);
    }

    function test_navigation() {
        const cover = createTemporaryObject(coverComponent, tc, {
            navigating: true,
            distance: 1234,
            maneuver: { type: 10, instruction: "Turn right onto High Street." },
            place: { name: "Tower Bridge", address: "London" }
        });
        verify(findChild(cover, "coverNavigation").visible);
        verify(!findChild(cover, "coverPlace").visible);
        compare(findChild(cover, "coverDistance").text, "1.2 km");
        compare(findChild(cover, "coverInstruction").text, "Turn right onto High Street.");
        compare(findChild(cover, "searchActions").enabled, false);
        compare(findChild(cover, "voiceActions").enabled, false);
        cover.voiceAvailable = true;
        verify(findChild(cover, "voiceActions").enabled);
        compare(findChild(cover, "muteAction").iconSource, "image://theme/icon-cover-speaker-mute");
        const spy = createTemporaryQmlObject("import QtTest; SignalSpy { signalName: \"muteToggled\" }", tc);
        spy.target = cover;
        findChild(cover, "muteAction").triggered();
        compare(spy.count, 1);
        cover.muted = true;
        compare(findChild(cover, "muteAction").iconSource, "image://theme/icon-cover-speaker");
        cover.arrived = true;
        verify(!findChild(cover, "coverDistance").visible);
    }
}
