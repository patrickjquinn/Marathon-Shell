import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "CalculatorPage"
    when: windowShown
    visible: true
    width: 720; height: 1440

    Component { id: appComponent; CalculatorApp { width: 720; height: 1440 } }

    function make() {
        const app = createTemporaryObject(appComponent, this);
        tryVerify(function () { return app.pageStack.currentPage !== null; });
        const page = app.pageStack.currentPage;
        tryVerify(function () { return page.activeFocus; });
        tryCompare(page, "status", PageStatus.Active);
        waitForRendering(page);
        return { calc: app.calc, page: page, app: app };
    }

    function key(page, name) {
        const k = findChild(page, "key_" + name);
        verify(k, "key " + name);
        return k;
    }

    function tap(page, name) {
        const k = key(page, name);
        mousePress(k);
        wait(Theme.minimumPressHighlightTime);
        mouseRelease(k);
        wait(Theme.minimumPressHighlightTime);
    }

    function test_keypadAddsNumbers() {
        const t = make();
        tap(t.page, "7");
        tap(t.page, "+");
        tap(t.page, "8");
        tap(t.page, "=");
        compare(t.calc.displayText, "15");
        compare(findChild(t.page, "display").text, "15");
        compare(findChild(t.page, "expression").text, "7 + 8");
    }

    function test_keysAreAccessibleButtons() {
        const t = make();
        compare(key(t.page, "÷").Accessible.name, "Divide");
        compare(key(t.page, "⌫").Accessible.name, "Delete");
        compare(key(t.page, "5").Accessible.name, "5");
        compare(key(t.page, "5").Accessible.role, Accessible.Button);
    }

    function test_keyActivatesFromKeyboard() {
        const t = make();
        const k = key(t.page, "9");
        k.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(t.calc.displayText, "9");
    }

    function test_scientificRowToggles() {
        const t = make();
        const row = findChild(t.page, "functionKeys");
        verify(row.visible);
        compare(row.children.length - 1, 12, "two full rows of six");
        t.page.scientific = false;
        verify(!row.visible);
    }

    function test_functionKey() {
        const t = make();
        tap(t.page, "8");
        tap(t.page, "1");
        tap(t.page, "√");
        compare(t.calc.displayText, "9");
    }

    function test_typedDigitsAndOperators() {
        const t = make();
        keyClick(Qt.Key_1);
        keyClick(Qt.Key_2);
        keyClick(Qt.Key_Asterisk);
        keyClick(Qt.Key_3);
        keyClick(Qt.Key_Return);
        compare(t.calc.displayText, "36");
        keyClick(Qt.Key_Minus);
        keyClick(Qt.Key_6);
        keyClick(Qt.Key_Enter);
        compare(t.calc.displayText, "30");
        keyClick(Qt.Key_Slash);
        keyClick(Qt.Key_4);
        keyClick(Qt.Key_Equal);
        compare(t.calc.displayText, "7.5");
        keyClick(Qt.Key_Plus);
        keyClick(Qt.Key_Period);
        keyClick(Qt.Key_5);
        keyClick(Qt.Key_Return);
        compare(t.calc.displayText, "8");
    }

    function test_typedBackspace() {
        const t = make();
        keyClick(Qt.Key_4);
        keyClick(Qt.Key_2);
        keyClick(Qt.Key_Backspace);
        compare(t.calc.displayText, "4");
    }

    function test_escapeClears() {
        const t = make();
        keyClick(Qt.Key_4);
        keyClick(Qt.Key_Plus);
        keyClick(Qt.Key_2);
        keyClick(Qt.Key_Escape);
        verify(t.calc.isClear);
        keyClick(Qt.Key_4);
        keyClick(Qt.Key_Delete);
        verify(t.calc.isClear);
    }

    SignalSpy { id: minimizeSpy; signalName: "minimizeRequested" }

    function test_escapeWhenClearIsBack() {
        const t = make();
        minimizeSpy.target = t.app;
        minimizeSpy.clear();
        keyClick(Qt.Key_Escape);
        compare(minimizeSpy.count, 1);
    }

    function test_typedPercent() {
        const t = make();
        keyClick(Qt.Key_5);
        keyClick(Qt.Key_Percent);
        compare(t.calc.displayText, "0.05");
    }

    function test_historyShowsCalculations() {
        const t = make();
        const list = findChild(t.page, "history");
        compare(list.count, 0);
        verify(findChild(t.page, "historyPlaceholder").visible);
        t.calc.press("2");
        t.calc.press("+");
        t.calc.press("2");
        t.calc.press("=");
        compare(list.count, 1);
        verify(!findChild(t.page, "historyPlaceholder").visible);
    }

    function test_undoMenuItem() {
        const t = make();
        const undo = findChild(t.page, "undoItem");
        verify(!undo.enabled);
        t.calc.press("5");
        verify(undo.enabled);
        undo.clicked();
        compare(t.calc.displayText, "0");
    }

    function test_modeMenuItem() {
        const t = make();
        const mode = findChild(t.page, "modeItem");
        compare(mode.text, "Basic mode");
        mode.clicked();
        verify(!t.page.scientific);
        compare(mode.text, "Scientific mode");
    }

    function test_pendingOperatorShownOnPage() {
        const t = make();
        tap(t.page, "7");
        tap(t.page, "+");
        const expr = findChild(t.page, "expression");
        verify(expr.visible);
        compare(expr.text, "7 +");
        verify(!findChild(t.page, "result").visible);
    }

    function openDisplayMenu(t) {
        const area = findChild(t.page, "displayArea");
        const menu = area.openMenu();
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        return menu;
    }

    function test_copyResult() {
        const t = make();
        t.calc.press("1");
        t.calc.press("2");
        t.calc.press("3");
        t.calc.press("4");
        Clipboard.text = "";
        mouseClick(findChild(openDisplayMenu(t), "copyItem"));
        tryCompare(Clipboard, "text", "1234");
    }

    function test_pasteNumber() {
        const t = make();
        Clipboard.text = "1 234,5";
        const menu = openDisplayMenu(t);
        const paste = findChild(menu, "pasteItem");
        verify(paste.visible);
        mouseClick(paste);
        tryCompare(t.calc, "displayText", "1,234.5");
    }

    function test_pasteHiddenForText() {
        const t = make();
        Clipboard.text = "hello";
        verify(!findChild(openDisplayMenu(t), "pasteItem").visible);
    }
}
