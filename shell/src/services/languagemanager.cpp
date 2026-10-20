#include "languagemanager.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

#include "marathon-shell-native/src/words.cxxqt.h"
#include "src/managers/settingsmanager.h"

LanguageManager::LanguageManager(SettingsManager *settingsManager, marathon::Dictionary *dictionary,
                                 QObject *parent)
    : QObject(parent)
    , m_settingsManager(settingsManager)
    , m_dictionary(dictionary) {
    if (m_settingsManager) {
        connect(m_settingsManager, &SettingsManager::keyboardLanguageChanged, this,
                &LanguageManager::onSettingsLanguageChanged);
    }

    initialize();
}

void LanguageManager::initialize() {
    m_availableLanguages = {"en_US", "fr_FR", "de_DE", "es_ES", "pt_BR",
                            "it_IT", "ru_RU", "ar_SA", "zh_CN", "ja_JP"};
    emit          availableLanguagesChanged();

    const QString savedLanguage =
        m_settingsManager ? m_settingsManager->keyboardLanguage() : QString();
    const QString languageToLoad =
        savedLanguage.isEmpty() ? QStringLiteral("en_US") : savedLanguage;
    loadLanguage(languageToLoad);
}

void LanguageManager::loadLanguage(const QString &languageId) {
    if (languageId.isEmpty()) {
        loadFallback();
        return;
    }

    const QVariantMap layout = parseLayoutFile(languageId);
    if (layout.isEmpty()) {
        loadFallback();
        return;
    }

    applyLayout(layout, languageId);
}

void LanguageManager::applyLayout(const QVariantMap &layout, const QString &languageId) {
    setCurrentLayout(layout);
    setCurrentLanguage(languageId);
    updateDictionary(layout, languageId);

    if (m_settingsManager && m_settingsManager->keyboardLanguage() != languageId) {
        m_settingsManager->setKeyboardLanguage(languageId);
    }

    emit languageChanged(languageId);
    emit layoutLoaded(layout);
}

void LanguageManager::loadFallback() {
    applyLayout(fallbackLayout(), QStringLiteral("en_US"));
}

QVariantMap LanguageManager::parseLayoutFile(const QString &languageId) const {
    const QString path =
        QStringLiteral(":/qt/qml/MarathonOS/Shell/qml/keyboard/Layouts/languages/%1.json")
            .arg(languageId);
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    const QByteArray    data = file.readAll();
    const QJsonDocument doc  = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        return {};
    }
    return doc.object().toVariantMap();
}

QVariantMap LanguageManager::fallbackLayout() const {
    return {
        {"id", "en_US"},
        {"name", "English (US)"},
        {"dictionary", "en_US"},
        {"rtl", false},
        {"rows",
         QVariantList{
             QVariantMap{{"keys",
                          QVariantList{QVariantMap{{"char", "q"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "w"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "e"},
                                                   {"alts", QVariantList{"è", "é", "ê", "ë", "ē"}}},
                                       QVariantMap{{"char", "r"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "t"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "y"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "u"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "i"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "o"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "p"}, {"alts", QVariantList{}}}}}},
             QVariantMap{{"keys",
                          QVariantList{QVariantMap{{"char", "a"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "s"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "d"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "f"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "g"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "h"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "j"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "k"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "l"}, {"alts", QVariantList{}}}}}},
             QVariantMap{{"keys",
                          QVariantList{QVariantMap{{"char", "z"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "x"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "c"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "v"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "b"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "n"}, {"alts", QVariantList{}}},
                                       QVariantMap{{"char", "m"}, {"alts", QVariantList{}}}}}}}}};
}

void LanguageManager::setCurrentLanguage(const QString &languageId) {
    if (m_currentLanguage == languageId) {
        return;
    }
    m_currentLanguage = languageId;
    emit currentLanguageChanged();
}

void LanguageManager::setCurrentLayout(const QVariantMap &layout) {
    if (m_currentLayout == layout) {
        return;
    }
    m_currentLayout = layout;
    emit currentLayoutChanged();
}

void LanguageManager::updateDictionary(const QVariantMap &layout, const QString &languageId) {
    if (!m_dictionary) {
        return;
    }
    const QString dictionary = layout.value("dictionary").toString();
    m_dictionary->setLanguage(dictionary.isEmpty() ? languageId : dictionary);
}

void LanguageManager::onSettingsLanguageChanged() {
    if (!m_settingsManager) {
        return;
    }
    const QString languageId = m_settingsManager->keyboardLanguage();
    if (languageId.isEmpty() || languageId == m_currentLanguage) {
        return;
    }
    loadLanguage(languageId);
}
