import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "ShareSheet"
    when: windowShown

    property var picked: []
    property int dismissals: 0

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        ShareSheet {
            id: sheet

            onChosen: id => tc.picked.push(id)
            onDismissed: tc.dismissals++
        }
    }

    function init() {
        picked = [];
        dismissals = 0;
    }

    function cleanup() {
        sheet.close(false);
        wait(20);
    }

    function test_aTargetTapHandsOverAndCloses() {
        sheet.open({
            title: "",
            text: "Buy milk",
            count: 1,
            targets: [{ id: "notes/text", name: "Notes", action: "New note", icon: "" }, { id: "clipboard", name: "Copy", glyph: "copy" }]
        });
        wait(50);
        compare(findChild(sheet, "sharePreviewText").text, "Buy milk");
        verify(!findChild(sheet, "shareNoTargets").visible);
        const notes = findChild(sheet, "shareTarget-notes/text");
        verify(notes.visible);
        verify(findChild(sheet, "sharePanel").y < win.height);
        mouseClick(notes);
        compare(picked, ["notes/text"]);
        compare(dismissals, 0);
        verify(!sheet.shown);
    }

    function test_aTapOutsideCancels() {
        sheet.open({ title: "Share image", count: 1, targets: [] });
        wait(50);
        verify(findChild(sheet, "shareNoTargets").visible);
        mouseClick(findChild(sheet, "shareScrim"), 10, 10);
        compare(dismissals, 1);
        compare(picked, []);
        verify(!sheet.shown);
    }

    function test_aPictureIsPreviewed() {
        sheet.open({ title: "", image: "file:///nonexistent/beach.png", count: 1, targets: [] });
        wait(50);
        verify(findChild(sheet, "sharePreviewImage").visible);
    }

    function test_androidAppsArriveAfter() {
        sheet.open({ title: "", text: "x", count: 1, targets: [{ id: "clipboard", name: "Copy", glyph: "copy" }] });
        sheet.addTargets([{ id: "android:org.signal/.Share", name: "Signal", icon: "data:image/png;base64,iVBORw0KGgo=" }]);
        wait(50);
        const signal = findChild(sheet, "shareTarget-android:org.signal/.Share");
        verify(signal && signal.visible);
        verify(findChild(signal, "shareTargetPicture").visible);
        mouseClick(signal);
        compare(picked, ["android:org.signal/.Share"]);
    }

    function test_targetsFitFourAcross() {
        const many = [];
        for (let i = 0; i < 6; ++i)
            many.push({ id: "app" + i + "/m", name: "App " + i, icon: "" });
        sheet.open({ title: "", count: 2, targets: many });
        wait(50);
        const first = findChild(sheet, "shareTarget-app0/m");
        const fifth = findChild(sheet, "shareTarget-app4/m");
        verify(first.width * 4 <= win.width);
        verify(fifth.y > first.y);
        compare(findChild(sheet, "sharePreviewText").text, "2 items");
    }
}
