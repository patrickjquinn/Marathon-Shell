import QtQuick
import QtQuick.Window
import QtTest
import Keel 1.0
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica
import "../../shell/qml/components/oobe"
import "../../shell/qml/core/LauncherGrid.js" as LauncherGrid

TestCase {
    name: "OobeLook"
    when: windowShown

    Window {
        width: 540
        height: 600
        visible: true

        OobeLook {
            id: look

            anchors.fill: parent
        }

        OobeSize {
            id: size

            anchors.fill: parent
            visible: false
        }
    }

    SignalSpy {
        id: lookDone

        target: look
        signalName: "done"
    }

    SignalSpy {
        id: sizeDone

        target: size
        signalName: "done"
    }

    function init() {
        SettingsManagerCpp.reduceMotion = false;
        SettingsManagerCpp.userScaleFactor = 1;
        SettingsManagerCpp.wallpaperPath = "";
        size.visible = false;
    }

    function test_thumbnailsListTheBuiltInWallpapers() {
        const strip = findChild(look, "wallpaperStrip");
        verify(strip);
        compare(strip.count, AmbienceService.wallpapers.length);
        for (const w of AmbienceService.wallpapers)
            verify(findChild(look, "wallpaper-" + w.name), w.name);
    }

    function test_tapSetsWallpaperAndRevealsFromTheThumbnail() {
        const w = AmbienceService.wallpapers[0];
        const thumb = findChild(look, "wallpaper-" + w.name);
        const preview = findChild(look, "lookPreview");
        mouseClick(thumb);
        compare(SettingsManagerCpp.wallpaperPath.toString(), w.path.toString());
        const c = thumb.mapToItem(preview, thumb.width / 2, thumb.height / 2);
        const reveal = preview.wallpaper;
        compare(reveal.centerX, c.x);
        compare(reveal.centerY, c.y);
        compare(reveal.duration, 450);
        tryVerify(() => reveal.revealing);
        tryVerify(() => !reveal.revealing, 3000);
        compare(reveal.current.toString(), w.path.toString());
        tryVerify(() => findChild(thumb, "ring").border.width > 0);
    }

    function test_reduceMotionCrossFades() {
        SettingsManagerCpp.reduceMotion = true;
        compare(findChild(look, "lookPreview").wallpaper.duration, 200);
    }

    function test_previewIsTheRealGridInTwoRows() {
        const grid = findChild(look, "lookPreview").grid;
        verify(grid);
        compare(grid.rows, 2);
    }

    function test_continueEmitsDone() {
        const button = findChild(look, "lookContinue");
        verify(button);
        mouseClick(button);
        compare(lookDone.count, 1);
    }

    function test_sliderWritesScaleAndGridFollows() {
        size.visible = true;
        const slider = findChild(size, "sizeSlider");
        verify(slider);
        compare(slider.minimumValue, 75);
        compare(slider.maximumValue, 150);
        compare(slider.stepSize, 5);
        slider.value = 150;
        compare(SettingsManagerCpp.userScaleFactor, 1.5);
        compare(slider.valueText, "150%");
        const grid = findChild(size, "sizePreview").grid;
        const before = grid.columns;
        Ambience.applyForwarded("/desktop/sailfish/silica/theme_pixel_ratio=" + 1.5 * Silica.Theme.pixelRatio);
        verify(grid.columns < before);
        compare(grid.columns, LauncherGrid.columns(540, Silica.Theme.pixelRatio, 0));
        mouseClick(findChild(size, "sizeContinue"));
        compare(sizeDone.count, 1);
    }
}
