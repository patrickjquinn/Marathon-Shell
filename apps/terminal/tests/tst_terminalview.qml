import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Terminal 1.0
import "../components"

TestCase {
    id: test

    name: "TerminalView"
    when: windowShown
    visible: true
    width: 540; height: 960

    Component {
        id: engineComponent
        TerminalEngine {}
    }
    Component {
        id: viewComponent
        TerminalView { width: 540; height: 960 }
    }
    SignalSpy { id: usedSpy; signalName: "modifiersUsed" }

    function makeView(props) {
        const view = createTemporaryObject(viewComponent, test, props || {});
        view.session = engineComponent.createObject(view);
        view.forceFocus();
        tryVerify(() => findChild(view, "renderer").activeFocus);
        return view;
    }

    function last(view) {
        const sent = view.session.sent;
        return sent[sent.length - 1];
    }

    function test_resizesTheShellToFit() {
        const view = makeView();
        const r = findChild(view, "renderer");
        compare(view.session.size, [Math.floor(r.width / 10), Math.floor(r.height / 20)]);
    }

    function test_textGoesToTheShell() {
        const view = makeView();
        keyClick("a");
        compare(last(view).input, "a");
    }

    function test_specialKeys_data() {
        return [Qt.Key_Escape, Qt.Key_Tab, Qt.Key_Return, Qt.Key_Backspace, Qt.Key_Up, Qt.Key_Left, Qt.Key_Home, Qt.Key_PageDown]
            .map(k => ({ tag: String(k), key: k }));
    }
    function test_specialKeys(data) {
        const view = makeView();
        keyClick(data.key);
        compare(last(view).key, data.key);
    }

    function test_ctrlLetter() {
        const view = makeView();
        keyClick(Qt.Key_C, Qt.ControlModifier);
        compare(last(view).key, Qt.Key_C);
        verify(last(view).modifiers & Qt.ControlModifier);
    }

    function test_backtab() {
        const view = makeView();
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier);
        compare(last(view).input, "\x1b[Z");
        verify(findChild(view, "renderer").activeFocus);
    }

    function test_unusedKeysPropagate() {
        const view = makeView();
        keyClick(Qt.Key_F1);
        compare(view.session.sent.length, 0);
    }

    // An armed Ctrl on the extra-keys row turns a typed letter into a control code.
    function test_extraCtrlAppliesToTypedText() {
        const view = makeView({ extraModifiers: Qt.ControlModifier });
        usedSpy.target = view;
        usedSpy.clear();
        keyClick("c");
        compare(last(view).key, Qt.Key_C);
        verify(last(view).modifiers & Qt.ControlModifier);
        compare(usedSpy.count, 1);
    }

    function test_extraAltSendsMeta() {
        const view = makeView({ extraModifiers: Qt.AltModifier });
        keyClick("b");
        compare(last(view).text, "b");
        compare(last(view).modifiers, Qt.AltModifier);
    }

    function test_ctrlDroppedFromSpecialKeys() {
        const view = makeView({ extraModifiers: Qt.ControlModifier });
        keyClick(Qt.Key_Up);
        compare(last(view).key, Qt.Key_Up);
        compare(last(view).modifiers & Qt.ControlModifier, 0);
    }

    function test_longPressSelects() {
        const view = makeView();
        const area = findChild(view, "touchArea");
        mousePress(area, 15, 25);
        tryVerify(() => findChild(view, "renderer").selected !== null, 3000);
        mouseMove(area, 55, 65);
        mouseRelease(area, 55, 65);
        compare(findChild(view, "renderer").selected, [1, 1, 5, 3]);
        compare(view.selection, "selected");
        mouseClick(area, 15, 25);
        compare(view.selection, "");
    }

    function test_copyButtonAppearsWhereTheSelectionEnds() {
        const view = makeView();
        const area = findChild(view, "touchArea");
        const copy = findChild(view, "copyButton");
        verify(!copy.visible);
        mousePress(area, 15, 400);
        tryVerify(() => findChild(view, "renderer").selected !== null, 3000);
        mouseMove(area, 200, 500);
        mouseRelease(area, 200, 500);
        verify(copy.visible);
        const end = area.mapToItem(view, 200, 500);
        verify(copy.y + copy.height < end.y);
        verify(copy.x <= end.x && copy.x + copy.width >= end.x);
        mouseClick(copy);
        compare(Clipboard.text, "selected");
        compare(view.selection, "");
        verify(!copy.visible);
    }

    function test_colorSchemes() {
        const view = makeView({ colorScheme: "light" });
        const r = findChild(view, "renderer");
        compare(r.backgroundColor, Qt.color("white"));
        view.colorScheme = "dark";
        compare(r.backgroundColor, Qt.color("black"));
        view.colorScheme = "ambience";
        compare(r.textColor, Theme.primaryColor);
    }

    function test_fontSize() {
        const view = makeView({ fontSize: 31 });
        compare(findChild(view, "renderer").font.pixelSize, 31);
    }
}
