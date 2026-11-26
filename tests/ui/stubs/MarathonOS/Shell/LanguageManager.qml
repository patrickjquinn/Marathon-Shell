pragma Singleton
import QtQml

QtObject {
    property var availableLanguages: ["en_US", "fr_FR", "pt_BR", "ar_SA"]
    property string currentLanguage: "en_US"
    property string currentLayout: ""
    function loadLanguage(id) {
        currentLanguage = id;
    }
}
