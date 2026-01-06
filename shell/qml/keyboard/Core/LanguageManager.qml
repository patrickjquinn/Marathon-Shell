pragma Singleton
import QtQuick

QtObject {
    id: languageManager

    property string currentLanguage: SettingsManagerCpp.keyboardLanguage || "en_US"
    property var currentLayout: null
    property var availableLanguages: []
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
    property var activeRequest: null

    signal languageChanged(string languageId)
    signal layoutLoaded(var layout)

    function initialize() {
        availableLanguages = ["en_US", "fr_FR", "de_DE", "es_ES", "pt_BR", "it_IT", "ru_RU", "ar_SA", "zh_CN", "ja_JP"];
        loadLanguage(currentLanguage);
    }

    function loadLanguage(languageId) {
        if (activeRequest) {
            activeRequest.onreadystatechange = null;
            activeRequest = null;
        }
        var xhr = new XMLHttpRequest();
        activeRequest = xhr;
        var url = Qt.resolvedUrl("../Layouts/languages/" + languageId + ".json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var response = xhr.responseText;
                        if (!response)
                            throw "Empty response text";

                        currentLayout = JSON.parse(response);
                        currentLanguage = languageId;
                        SettingsManagerCpp.keyboardLanguage = languageId;
                        if (typeof WordEngine !== 'undefined' && WordEngine !== null)
                            WordEngine.setLanguage(currentLayout.dictionary || languageId);

                        languageChanged(languageId);
                        layoutLoaded(currentLayout);
                    } catch (e) {
                        console.error("[LanguageManager] Error parsing layout JSON: " + e);
                        loadFallback();
                    }
                } else {
                    console.error("[LanguageManager] Failed to load layout file. Status: " + xhr.status);
                    loadFallback();
                }
                activeRequest = null;
            }
        };
        xhr.onerror = function () {
            console.error("[LanguageManager] XHR Network Error");
            loadFallback();
        };
        try {
            xhr.open("GET", url);
            xhr.send();
        } catch (e) {
            console.error("[LanguageManager] XHR Exception: " + e);
            loadFallback();
        }
    }

    function loadFallback() {
        console.warn("[LanguageManager] Loading fallback layout (English US)");
        currentLayout = {
            "id": "en_US",
            "name": "English (US)",
            "dictionary": "en_US",
            "rtl": false,
            "rows": [
                {
                    "keys": [
                        {
                            "char": "q",
                            "alts": []
                        },
                        {
                            "char": "w",
                            "alts": []
                        },
                        {
                            "char": "e",
                            "alts": ["è", "é", "ê", "ë", "ē"]
                        },
                        {
                            "char": "r",
                            "alts": []
                        },
                        {
                            "char": "t",
                            "alts": []
                        },
                        {
                            "char": "y",
                            "alts": []
                        },
                        {
                            "char": "u",
                            "alts": []
                        },
                        {
                            "char": "i",
                            "alts": []
                        },
                        {
                            "char": "o",
                            "alts": []
                        },
                        {
                            "char": "p",
                            "alts": []
                        }
                    ]
                },
                {
                    "keys": [
                        {
                            "char": "a",
                            "alts": []
                        },
                        {
                            "char": "s",
                            "alts": []
                        },
                        {
                            "char": "d",
                            "alts": []
                        },
                        {
                            "char": "f",
                            "alts": []
                        },
                        {
                            "char": "g",
                            "alts": []
                        },
                        {
                            "char": "h",
                            "alts": []
                        },
                        {
                            "char": "j",
                            "alts": []
                        },
                        {
                            "char": "k",
                            "alts": []
                        },
                        {
                            "char": "l",
                            "alts": []
                        }
                    ]
                },
                {
                    "keys": [
                        {
                            "char": "z",
                            "alts": []
                        },
                        {
                            "char": "x",
                            "alts": []
                        },
                        {
                            "char": "c",
                            "alts": []
                        },
                        {
                            "char": "v",
                            "alts": []
                        },
                        {
                            "char": "b",
                            "alts": []
                        },
                        {
                            "char": "n",
                            "alts": []
                        },
                        {
                            "char": "m",
                            "alts": []
                        }
                    ]
                }
            ]
        };
        currentLanguage = "en_US";
        layoutLoaded(currentLayout);
    }

    function nextLanguage() {
        var idx = availableLanguages.indexOf(currentLanguage);
        var nextIdx = (idx + 1) % availableLanguages.length;
        loadLanguage(availableLanguages[nextIdx]);
    }

    function getFlag(languageId) {
        return languageFlags[languageId] || "🌐";
    }

    function getName(languageId) {
        if (!currentLayout || currentLayout.id !== languageId)
            return languageId;

        return currentLayout.name || languageId;
    }

    Component.onCompleted: initialize()
}
