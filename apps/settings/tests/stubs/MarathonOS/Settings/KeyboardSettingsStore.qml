pragma Singleton
import QtQml

QtObject {
    property string currentLanguage: "en_US"
    property bool autoCorrectEnabled: true
    property bool autoCapitalizeEnabled: true
    property bool hapticFeedbackEnabled: true
    property bool predictionsEnabled: true
    readonly property var availableLanguages: ["en_US", "de_DE", "fr_FR"]

    function reset() {
        currentLanguage = "en_US";
        autoCorrectEnabled = true;
        autoCapitalizeEnabled = true;
        hapticFeedbackEnabled = true;
        predictionsEnabled = true;
    }
    function getLanguageName(id) {
        return { en_US: "English (US)", de_DE: "Deutsch", fr_FR: "Français" }[id] || id;
    }
}
