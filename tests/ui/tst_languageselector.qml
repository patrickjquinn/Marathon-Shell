import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../shell/qml/keyboard/UI"

TestCase {
    name: "LanguageSelector"
    when: windowShown

    Window {
        width: 360
        height: 720
        visible: true

        LanguageSelector {
            id: selector
            width: 360
            visible: true
        }
    }

    SignalSpy { id: selectedSpy; target: selector; signalName: "languageSelected" }

    function row(id) {
        return findChild(selector, "language_" + id);
    }

    function test_rowsShowNativeNames() {
        tryVerify(() => row("fr_FR") !== null);
        compare(row("fr_FR").text, "Français");
        compare(row("pt_BR").text, "Português");
        verify(row("en_US").text.indexOf("\uD83C") < 0, "no flag emoji");
    }

    function test_currentLanguageUsesTheHighlight() {
        LanguageManager.currentLanguage = "en_US";
        verify(row("en_US").current);
        verify(!row("fr_FR").current);
    }

    function test_tapSelects() {
        selectedSpy.clear();
        mouseClick(row("fr_FR"));
        compare(selectedSpy.count, 1);
        compare(selectedSpy.signalArguments[0][0], "fr_FR");
        compare(LanguageManager.currentLanguage, "fr_FR");
        LanguageManager.currentLanguage = "en_US";
    }
}
