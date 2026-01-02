pragma Singleton
import MarathonOS.Shell
import QtQuick

QtObject {
    id: keyboardSettingsStore

    property string currentLanguage: SettingsManagerCpp.keyboardLanguage || "en_US"
    property bool autoCorrectEnabled: SettingsManagerCpp.keyboardAutoCorrection
    property bool autoCapitalizeEnabled: true
    property bool hapticFeedbackEnabled: SettingsManagerCpp.keyboardHapticStrength !== "off"
    property bool predictionsEnabled: SettingsManagerCpp.keyboardPredictiveText
    readonly property var availableLanguages: ["en_US", "fr_FR", "de_DE", "es_ES", "pt_BR", "it_IT", "ru_RU", "ar_SA", "zh_CN", "ja_JP"]
    readonly property var languageNames: {
        "en_US": "English (US)",
        "fr_FR": "Français",
        "de_DE": "Deutsch",
        "es_ES": "Español",
        "pt_BR": "Português",
        "it_IT": "Italiano",
        "ru_RU": "Русский",
        "ar_SA": "العربية",
        "zh_CN": "中文",
        "ja_JP": "日本語"
    }
    readonly property var languageFlags: {
        "en_US": "🇺🇸",
        "fr_FR": "🇫🇷",
        "de_DE": "🇩🇪",
        "es_ES": "🇪🇸",
        "pt_BR": "🇧🇷",
        "it_IT": "🇮🇹",
        "ru_RU": "🇷🇺",
        "ar_SA": "🇸🇦",
        "zh_CN": "🇨🇳",
        "ja_JP": "🇯🇵"
    }

    function getLanguageName(languageId) {
        return languageNames[languageId] || languageId;
    }

    function getFlag(languageId) {
        return languageFlags[languageId] || "🌐";
    }

    onCurrentLanguageChanged: {
        SettingsManagerCpp.keyboardLanguage = currentLanguage;
    }
    onAutoCorrectEnabledChanged: {
        SettingsManagerCpp.keyboardAutoCorrection = autoCorrectEnabled;
    }
    onHapticFeedbackEnabledChanged: {
        SettingsManagerCpp.keyboardHapticStrength = hapticFeedbackEnabled ? "medium" : "off";
    }
    onPredictionsEnabledChanged: {
        SettingsManagerCpp.keyboardPredictiveText = predictionsEnabled;
    }
}
