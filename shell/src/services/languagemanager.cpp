#include "languagemanager.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

#include "qml/keyboard/Data/WordEngine.h"
#include "src/managers/settingsmanager.h"

LanguageManager::LanguageManager(SettingsManager *settingsManager, WordEngine *wordEngine,
                                 QObject *parent)
    : QObject(parent)
    , m_settingsManager(settingsManager)
    , m_wordEngine(wordEngine) {
    m_languageFlags = {{"en_US", "🇺🇸"}, {"fr_FR", "🇫🇷"}, {"de_DE", "🇩🇪"}, {"es_ES", "🇪🇸"},
                       {"pt_BR", "🇧🇷"}, {"it_IT", "🇮🇹"}, {"ru_RU", "🇷🇺"}, {"ar_SA", "🇸🇦"},
                       {"zh_CN", "🇨🇳"}, {"ja_JP", "🇯🇵"}};

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

void LanguageManager::nextLanguage() {
    if (m_availableLanguages.isEmpty()) {
        return;
    }
    const int currentIndex = m_availableLanguages.indexOf(m_currentLanguage);
    const int nextIndex    = (currentIndex + 1) % m_availableLanguages.size();
    loadLanguage(m_availableLanguages.at(nextIndex));
}

QString LanguageManager::getFlag(const QString &languageId) const {
    const QVariant flag = m_languageFlags.value(languageId);
    return flag.isValid() ? flag.toString() : QStringLiteral("🌐");
}

QString LanguageManager::getName(const QString &languageId) const {
    if (m_currentLayout.value("id").toString() != languageId) {
        return languageId;
    }
    const QString name = m_currentLayout.value("name").toString();
    return name.isEmpty() ? languageId : name;
}

void LanguageManager::applyLayout(const QVariantMap &layout, const QString &languageId) {
    setCurrentLayout(layout);
    setCurrentLanguage(languageId);
    updateWordEngine(layout, languageId);

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

void LanguageManager::updateWordEngine(const QVariantMap &layout, const QString &languageId) {
    if (!m_wordEngine) {
        return;
    }
    const QString dictionary = layout.value("dictionary").toString();
    m_wordEngine->setLanguage(dictionary.isEmpty() ? languageId : dictionary);
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
