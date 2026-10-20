#pragma once

#include <QPointer>
#include <QVariantMap>
#include <QObject>
#include <QStringList>
#include <qqml.h>

class SettingsManager;
namespace marathon {
    class Dictionary;
}

class LanguageManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString currentLanguage READ currentLanguage NOTIFY currentLanguageChanged)
    Q_PROPERTY(QVariantMap currentLayout READ currentLayout NOTIFY currentLayoutChanged)
    Q_PROPERTY(
        QStringList availableLanguages READ availableLanguages NOTIFY availableLanguagesChanged)

  public:
    explicit LanguageManager(SettingsManager *settingsManager, marathon::Dictionary *dictionary,
                             QObject *parent = nullptr);

    QString currentLanguage() const {
        return m_currentLanguage;
    }
    QVariantMap currentLayout() const {
        return m_currentLayout;
    }
    QStringList availableLanguages() const {
        return m_availableLanguages;
    }

    Q_INVOKABLE void    initialize();
    Q_INVOKABLE void    loadLanguage(const QString &languageId);

  signals:
    void currentLanguageChanged();
    void currentLayoutChanged();
    void availableLanguagesChanged();
    void languageChanged(const QString &languageId);
    void layoutLoaded(const QVariantMap &layout);

  private:
    void        applyLayout(const QVariantMap &layout, const QString &languageId);
    void        loadFallback();
    QVariantMap parseLayoutFile(const QString &languageId) const;
    QVariantMap fallbackLayout() const;
    void        setCurrentLanguage(const QString &languageId);
    void        setCurrentLayout(const QVariantMap &layout);
    void        updateDictionary(const QVariantMap &layout, const QString &languageId);
    void        onSettingsLanguageChanged();

    QPointer<SettingsManager> m_settingsManager;
    QPointer<marathon::Dictionary> m_dictionary;
    QString                   m_currentLanguage;
    QVariantMap               m_currentLayout;
    QStringList               m_availableLanguages;
};
