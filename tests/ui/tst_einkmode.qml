import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../shell/qml/components"
import "../../shell/qml/keyboard/UI"

// E-paper (docs/design/EINK_MODE.md): ink on paper from the panel's 16
// greys, and its own Refresh control. MColors.eink and Display stand in for
// DeviceProfile and the panel.
TestCase {
    id: tc

    name: "EinkMode"
    when: windowShown

    Window {
        width: 600
        height: 800
        visible: true

        MarathonQuickSettings {
            id: qs

            width: 600
            height: drawnHeight
            maxHeight: 640
        }

        WallpaperTone {
            id: tone

            width: 100
            height: 20
        }

        Key {
            id: shiftKey

            y: 700
            width: 60
            text: "shift"
            iconName: "chevron-up"
            isSpecial: true
        }
    }

    QtObject {
        id: shellStub

        property real maxQuickSettingsHeight: 640
    }

    function initTestCase() {
        UIStore.shellRef = shellStub;
    }

    function cleanupTestCase() {
        UIStore.shellRef = null;
    }

    function init() {
        MColors.eink = false;
        Display.refreshControls = false;
        Display.fullRefreshes = 0;
        UIStore.quickSettingsOpen = true;
        UIStore.quickSettingsHeight = qs.maxHeight;
    }

    function cleanup() {
        MColors.eink = false;
        Display.refreshControls = false;
    }

    // An opaque grey on one of the panel's 16 levels.
    function onPanelLevel(c) {
        const level = c.r * 15;
        return c.a === 1 && c.r === c.g && c.g === c.b && Math.abs(level - Math.round(level)) < 1e-3;
    }

    function test_paletteIsThePanelsGreys() {
        verify(!onPanelLevel(MColors.background) || MColors.background.r < 0.1, "LCD keeps its near-black");
        MColors.eink = true;
        for (const name of ["elev0", "elev1", "elev2", "elev3", "elev4", "elev5", "bb10Black", "bb10Surface", "bb10Elevated", "bb10Card", "textOnAccent", "borderGlass", "barDark", "barLight", "error", "warning", "accentFill", "controlFill", "background", "surface", "elevated"])
            verify(onPanelLevel(MColors[name]), name + " " + MColors[name]);
        compare(MColors.background, Qt.color("#ffffff"));
        compare(MColors.accentFill, Qt.color("#000000"));
        compare(MColors.textOnAccent, Qt.color("#ffffff"));
        compare(MColors.ripple.a, 0);
        compare(MColors.tealHalo.a, 0);
    }

    // Toasts and the HUD: paper with an ink edge, not dark glass.
    function test_badgesAreInkOnPaper() {
        fuzzyCompare(MColors.badge.a, 0.85, 0.01);
        MColors.eink = true;
        compare(MColors.badge, Qt.color("#ffffff"));
        compare(MColors.badgeEdgeOpacity, 1);
    }

    // On paper an overlay darkens by whole grey steps.
    function test_overlaysDarkenOnPaper() {
        MColors.eink = true;
        compare(MColors.whiteOverlay08.r, 0);
        fuzzyCompare(MColors.whiteOverlay08.a, 1 / 15, 0.005);
        fuzzyCompare(MColors.whiteOverlay16.a, 2 / 15, 0.005);
    }

    // Home's labels sit on paper, not on a wallpaper the frame reads dark.
    function test_textOnTheBackdropIsInk() {
        tone.light = false;
        compare(tone.target, Silica.Theme.lightPrimaryColor);
        MColors.eink = true;
        compare(tone.target, Silica.Theme.darkPrimaryColor);
        tone.light = Qt.binding(() => tone.fallbackLight);
    }

    function test_refreshTileOnlyWithRefreshControls() {
        compare(qs.tileById("refresh"), null);
        Display.refreshControls = true;
        const tile = qs.tileById("refresh");
        verify(tile !== null);
        compare(qs.tiles[0].id, "refresh");
        compare(tile.on, false);
    }

    // The clear waits for a still screen, so the shade closes first.
    function test_refreshTileClosesTheShadeAndClears() {
        Display.refreshControls = true;
        const closed = signalSpy.createObject(tc, {
            target: qs,
            signalName: "closed"
        });
        qs.toggle("refresh");
        compare(Display.fullRefreshes, 1);
        compare(closed.count, 1);
        closed.destroy();
    }

    // A special key's cap is a grey the panel has, not a dither between two.
    function test_specialKeyCapIsAPanelGrey() {
        MColors.eink = true;
        const cap = shiftKey.children.find(c => c.color !== undefined && c.radius > 0);
        verify(cap, "the cap");
        verify(onPanelLevel(cap.color), "cap " + cap.color);
    }

    Component {
        id: signalSpy

        SignalSpy {}
    }
}
