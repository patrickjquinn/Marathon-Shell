import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "QuickSettings"
    when: windowShown

    Window {
        width: 720
        height: Math.max(720, Math.min(fit.height, 1400))
        visible: true

        MarathonQuickSettings {
            id: qs
            width: 720
            height: UIStore.quickSettingsHeight
            maxHeight: fit.height
        }

        QtObject {
            id: fit
            property real height: 400
        }
    }

    function init() {
        fit.height = 400;
        UIStore.quickSettingsOpen = true;
        UIStore.quickSettingsHeight = qs.maxHeight;
        scroll().cancelFlick();
        scroll().contentY = 0;
        wait(0);
    }

    function scroll() {
        return findChild(qs, "shadeScroll");
    }

    function touchDrag(y0, dy, x) {
        x = x === undefined ? 4 : x;
        const steps = 10;
        const seq = touchEvent(qs);
        seq.press(0, qs, x, y0).commit();
        for (let i = 1; i <= steps; ++i) {
            wait(16);
            seq.move(0, qs, x, y0 + dy * i / steps).commit();
        }
        seq.release(0, qs, x, y0 + dy).commit();
        wait(50);
    }

    function mouseDrag(y0, dy, x) {
        x = x === undefined ? 4 : x;
        const steps = 10;
        mousePress(qs, x, y0);
        for (let i = 1; i <= steps; ++i)
            mouseMove(qs, x, y0 + dy * i / steps, 16);
        mouseRelease(qs, x, y0 + dy);
        wait(50);
    }

    function test_contentOverflows() {
        verify(scroll().contentHeight > qs.maxHeight, "content " + scroll().contentHeight + " vs " + qs.maxHeight);
        verify(scroll().interactive);
    }

    function test_swipeUpScrollsOverflowingContent_data() {
        return [
            { tag: "touch margin", touch: true, x: 4 },
            { tag: "mouse margin", touch: false, x: 4 },
            { tag: "touch tiles", touch: true, x: 90 },
            { tag: "mouse tiles", touch: false, x: 90 },
            { tag: "touch centre", touch: true, x: 360 },
            { tag: "mouse centre", touch: false, x: 360 }
        ];
    }

    function test_swipeUpScrollsOverflowingContent(data) {
        data.touch ? touchDrag(300, -150, data.x) : mouseDrag(300, -150, data.x);
        verify(UIStore.quickSettingsOpen, "shade stays open");
        compare(UIStore.quickSettingsHeight, qs.maxHeight);
        verify(scroll().contentY > 0, "content scrolled");
    }

    function test_swipeUpAtTheEndCloses_data() {
        return test_swipeUpScrollsOverflowingContent_data();
    }

    function test_swipeUpAtTheEndCloses(data) {
        const f = scroll();
        f.contentY = f.contentHeight - f.height;
        verify(f.atYEnd);
        data.touch ? touchDrag(300, -200, data.x) : mouseDrag(300, -200, data.x);
        verify(!UIStore.quickSettingsOpen);
    }

    function test_swipeDownAtTheEndScrollsBack_data() {
        return test_swipeUpScrollsOverflowingContent_data();
    }

    function test_swipeDownAtTheEndScrollsBack(data) {
        const f = scroll();
        const end = f.contentHeight - f.height;
        f.contentY = end;
        data.touch ? touchDrag(100, 150, data.x) : mouseDrag(100, 150, data.x);
        verify(UIStore.quickSettingsOpen);
        compare(UIStore.quickSettingsHeight, qs.maxHeight);
        tryVerify(() => f.contentY < end, 1000, "content scrolled back");
    }

    function test_swipeUpClosesWhenContentFits_data() {
        return test_swipeUpScrollsOverflowingContent_data();
    }

    function test_swipeUpClosesWhenContentFits(data) {
        fit.height = 5000;
        UIStore.quickSettingsHeight = qs.maxHeight;
        verify(!scroll().interactive);
        data.touch ? touchDrag(500, -400, data.x) : mouseDrag(500, -400, data.x);
        verify(!UIStore.quickSettingsOpen);
    }

    // The shade opens to the space it is given, not to its content.
    function test_shortContentFillsShade() {
        fit.height = scroll().contentHeight + 200;
        UIStore.quickSettingsHeight = qs.maxHeight;
        compare(qs.height, fit.height);
        verify(!scroll().interactive);
        const img = grabImage(qs);
        compare(img.pixel(360, qs.height - 10).a, 1, "opaque below the content");
        touchDrag(qs.height - 20, -300, 360);
        verify(!UIStore.quickSettingsOpen);
    }

    function brightnessSlider() {
        return findChild(qs, "brightnessSlider");
    }

    // Horizontal drag along the slider track, with optional vertical wobble.
    // Returns the values seen after each move.
    function sliderDrag(touch, wobble, steps) {
        const s = brightnessSlider();
        const track = findChild(s, "sliderTrack");
        const p0 = track.mapToItem(qs, track.width * 0.2, track.height / 2);
        const dx = track.width * 0.6;
        steps = steps || 20;
        const seen = [];
        const seq = touch ? touchEvent(qs) : null;
        touch ? seq.press(0, qs, p0.x, p0.y).commit() : mousePress(qs, p0.x, p0.y);
        for (let i = 1; i <= steps; ++i) {
            const x = p0.x + dx * i / steps;
            const y = p0.y + (i % 2 ? wobble : -wobble) * Math.min(1, i / 4);
            if (touch)
                seq.move(0, qs, x, y).commit();
            else
                mouseMove(qs, x, y);
            // Touch moves are delivered on the next frame.
            wait(20);
            seen.push(SystemControlStore.brightness);
        }
        touch ? seq.release(0, qs, p0.x + dx, p0.y).commit() : mouseRelease(qs, p0.x + dx, p0.y);
        wait(50);
        return seen;
    }

    // At the overflowing height the sliders start below the fold; leave
    // room above them so a scroll is observable.
    function revealSliders(toEnd) {
        const f = scroll();
        if (f.interactive)
            f.contentY = (f.contentHeight - f.height) / (toEnd ? 1 : 2);
    }

    function test_sliderDrags_data() {
        const rows = [];
        for (const touch of [true, false])
            for (const wobble of [0, 12, 30])
                for (const fits of ["overflows", "end", "fits"])
                    for (const steps of [20, 4])
                        rows.push({ tag: (touch ? "touch" : "mouse") + " wobble " + wobble + " " + fits + " steps " + steps, touch: touch, wobble: wobble, fits: fits, steps: steps });
        return rows;
    }

    function test_sliderDrags(data) {
        if (data.fits === "fits") {
            fit.height = 5000;
            UIStore.quickSettingsHeight = qs.maxHeight;
        }
        revealSliders(data.fits === "end");
        const y = scroll().contentY;
        SystemControlStore.brightness = 0;
        const seen = sliderDrag(data.touch, data.wobble, data.steps);
        verify(UIStore.quickSettingsOpen, "shade stays open");
        compare(UIStore.quickSettingsHeight, qs.maxHeight);
        compare(scroll().contentY, y);
        verify(seen[seen.length - 1] > 70, "value followed the drag: " + seen);
        for (let i = 1; i < seen.length; ++i)
            verify(seen[i] >= seen[i - 1], "monotonic: " + seen);
        verify(seen[seen.length / 2] > 30 && seen[seen.length / 2] < 70, "continuous: " + seen);
    }

    function test_verticalSwipeOnSliderScrolls_data() {
        return [{ tag: "touch", touch: true }, { tag: "mouse", touch: false }];
    }

    function test_verticalSwipeOnSliderScrolls(data) {
        revealSliders();
        const y = scroll().contentY;
        const track = findChild(brightnessSlider(), "sliderTrack");
        const p = track.mapToItem(qs, track.width / 2, track.height / 2);
        const before = SystemControlStore.brightness = 40;
        data.touch ? touchDrag(p.y, -150, p.x) : mouseDrag(p.y, -150, p.x);
        verify(UIStore.quickSettingsOpen);
        verify(scroll().contentY > y, "content scrolled");
        verify(Math.abs(SystemControlStore.brightness - before) < 10, "barely moved: " + SystemControlStore.brightness);
    }

    SignalSpy { id: launchSpy; target: qs; signalName: "launchApp" }

    // AppLaunchService resolves an app by its "id" key.
    function test_settingsButtonLaunchesSettings() {
        launchSpy.clear();
        mouseClick(findChild(qs, "settingsButton"));
        compare(launchSpy.count, 1);
        compare(launchSpy.signalArguments[0][0].id, "settings");
    }
}
