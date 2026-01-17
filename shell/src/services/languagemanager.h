#pragma once

#include <QPointer>
#include <QVariantMap>
#include <QObject>
#include <QStringList>
#include <qqml.h>

class SettingsManager;
class WordEngine;

class LanguageManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString currentLanguage READ currentLanguage NOTIFY currentLanguageChanged)
    Q_PROPERTY(QVariantMap currentLayout READ currentLayout NOTIFY currentLayoutChanged)
    Q_PROPERTY(
        QStringList availableLanguages READ availableLanguages NOTIFY availableLanguagesChanged)
    Q_PROPERTY(QVariantMap languageFlags READ languageFlags CONSTANT)

  public:
    explicit LanguageManager(SettingsManager *settingsManager, WordEngine *wordEngine,
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
    QVariantMap languageFlags() const {
        return m_languageFlags;
    }

    Q_INVOKABLE void    initialize();
    Q_INVOKABLE void    loadLanguage(const QString &languageId);
    Q_INVOKABLE void    nextLanguage();
    Q_INVOKABLE QString getFlag(const QString &languageId) const;
    Q_INVOKABLE QString getName(const QString &languageId) const;

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
    void        updateWordEngine(const QVariantMap &layout, const QString &languageId);
    void        onSettingsLanguageChanged();

    QPointer<SettingsManager> m_settingsManager;
    QPointer<WordEngine>      m_wordEngine;
    QString                   m_currentLanguage;
    QVariantMap               m_currentLayout;
    QStringList               m_availableLanguages;
    QVariantMap               m_languageFlags;
};
