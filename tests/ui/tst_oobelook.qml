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
        height: 1140
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
        id: chosen

        target: look
        signalName: "wallpaperChosen"
    }

    SignalSpy {
        id: sizeDone

        target: size
        signalName: "done"
    }

    readonly property string old: AmbienceService.wallpapers[1].path.toString()

    function init() {
        MMotion.reduceMotion = false;
        SettingsManagerCpp.userScaleFactor = 1;
        SettingsManagerCpp.wallpaperPath = "";
        size.visible = false;
        wait(50);
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
        SettingsManagerCpp.wallpaperPath = old;
        mouseClick(thumb);
        compare(SettingsManagerCpp.wallpaperPath.toString(), w.path.toString());
        const c = thumb.mapToItem(preview, thumb.width / 2, thumb.height / 2);
        const reveal = preview.wallpaper;
        compare(reveal.centerX, c.x);
        compare(reveal.centerY, c.y);
        compare(reveal.duration, 450);
        tryVerify(() => reveal.revealing);
        compare(reveal.current.toString(), old);
        compare(reveal.target.toString(), w.path.toString());
        tryVerify(() => !reveal.revealing, 3000);
        compare(reveal.current.toString(), w.path.toString());
        tryVerify(() => findChild(thumb, "ring").border.width > 0);
    }

    function test_tapEmitsWallpaperChosenOnce() {
        SettingsManagerCpp.wallpaperPath = old;
        chosen.clear();
        const w = AmbienceService.wallpapers[1];
        const thumb = findChild(look, "wallpaper-" + w.name);
        mouseClick(thumb);
        compare(chosen.count, 1);
        const args = chosen.signalArguments[0];
        compare(args[0].toString(), old);
        compare(args[1].toString(), w.path.toString());
        const c = thumb.mapToItem(null, thumb.width / 2, thumb.height / 2);
        compare(args[2].x, c.x);
        compare(args[2].y, c.y);
    }

    function test_reduceMotionCrossFades() {
        MMotion.reduceMotion = true;
        compare(findChild(look, "lookPreview").wallpaper.duration, 200);
    }

    function test_previewIsTheRealGridInTwoRows() {
        const grid = findChild(look, "lookPreview").grid;
        verify(grid);
        compare(grid.rows, 2);
    }

    function test_openingSizeKeepsTheStoredScale() {
        SettingsManagerCpp.userScaleFactor = 1.03;
        size.visible = true;
        wait(400);
        compare(SettingsManagerCpp.userScaleFactor, 1.03);
    }

    function test_sliderStepsThroughSettingsSizes() {
        size.visible = true;
        const slider = findChild(size, "sizeSlider");
        const labels = [];
        for (let i = slider.minimumValue; i <= slider.maximumValue; i += slider.stepSize) {
            slider.value = i;
            labels.push(slider.valueText);
        }
        compare(labels, ["75%", "90%", "100%", "110%", "125%", "140%", "150%"]);
        slider.value = 2;
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
        compare(slider.valueText, "100%");
        mousePress(slider, slider.width / 2, slider.height / 2);
        mouseMove(slider, slider.width / 2 + 20, slider.height / 2);
        mouseMove(slider, slider.width - 1, slider.height / 2);
        compare(slider.valueText, "150%");
        compare(SettingsManagerCpp.userScaleFactor, 1);
        mouseRelease(slider, slider.width - 1, slider.height / 2);
        compare(SettingsManagerCpp.userScaleFactor, 1.5);
        const grid = findChild(size, "sizePreview").grid;
        const before = grid.columns;
        const ratio = Silica.Theme.pixelRatio;
        Ambience.applyForwarded("/desktop/sailfish/silica/theme_pixel_ratio=" + 1.5 * Silica.Theme.pixelRatio);
        verify(grid.columns < before);
        compare(grid.columns, LauncherGrid.columns(540, Silica.Theme.pixelRatio, 0));
        Ambience.applyForwarded("/desktop/sailfish/silica/theme_pixel_ratio=" + ratio);
        mouseClick(findChild(size, "sizeContinue"));
        compare(sizeDone.count, 1);
    }

    property real shortRatio: 0

    function cleanup() {
        if (shortRatio > 0)
            Ambience.applyForwarded("/desktop/sailfish/silica/theme_pixel_ratio=" + shortRatio);
        shortRatio = 0;
        size.anchors.fill = size.parent;
        look.anchors.fill = look.parent;
    }

    function test_shortScreenStillShowsAWholeRow() {
        shortRatio = Silica.Theme.pixelRatio;
        size.anchors.fill = undefined;
        size.width = 540;
        size.height = 700;
        size.visible = true;
        Ambience.applyForwarded("/desktop/sailfish/silica/theme_pixel_ratio=" + 1.5 * shortRatio);
        const preview = findChild(size, "sizePreview");
        const button = findChild(size, "sizeContinue");
        tryVerify(() => preview.height >= preview.gridTop + preview.cellHeight - 0.5);
        tryVerify(() => button.mapToItem(size, 0, button.height).y <= size.height);
    }

    function test_shortScreenLookStillShowsAWholeRow() {
        shortRatio = Silica.Theme.pixelRatio;
        look.anchors.fill = undefined;
        look.width = 540;
        look.height = 700;
        Ambience.applyForwarded("/desktop/sailfish/silica/theme_pixel_ratio=" + 1.5 * shortRatio);
        const preview = findChild(look, "lookPreview");
        tryVerify(() => preview.height >= preview.gridTop + preview.cellHeight - 0.5);
        const button = findChild(look, "lookContinue");
        tryVerify(() => button.mapToItem(look, 0, button.height).y <= look.height);
    }
}
