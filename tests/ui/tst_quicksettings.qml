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
        height: 720
        visible: true

        MarathonQuickSettings {
            id: qs
            width: 720
            height: UIStore.quickSettingsHeight
            maxHeight: Math.min(fit.height, preferredHeight)
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
        verify(qs.preferredHeight > qs.maxHeight, "content " + qs.preferredHeight + " vs " + qs.maxHeight);
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
}
