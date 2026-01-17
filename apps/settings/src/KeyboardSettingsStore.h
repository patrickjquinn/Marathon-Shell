#pragma once

#include <QPointer>
#include <QVariantMap>
#include <QObject>
#include <QStringList>
#include <qqml.h>

class KeyboardSettingsStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString currentLanguage READ currentLanguage WRITE setCurrentLanguage NOTIFY
                   currentLanguageChanged)
    Q_PROPERTY(bool autoCorrectEnabled READ autoCorrectEnabled WRITE setAutoCorrectEnabled NOTIFY
                   autoCorrectEnabledChanged)
    Q_PROPERTY(bool autoCapitalizeEnabled READ autoCapitalizeEnabled WRITE setAutoCapitalizeEnabled
                   NOTIFY autoCapitalizeEnabledChanged)
    Q_PROPERTY(bool hapticFeedbackEnabled READ hapticFeedbackEnabled WRITE setHapticFeedbackEnabled
                   NOTIFY hapticFeedbackEnabledChanged)
    Q_PROPERTY(bool predictionsEnabled READ predictionsEnabled WRITE setPredictionsEnabled NOTIFY
                   predictionsEnabledChanged)
    Q_PROPERTY(QStringList availableLanguages READ availableLanguages CONSTANT)
    Q_PROPERTY(QVariantMap languageNames READ languageNames CONSTANT)
    Q_PROPERTY(QVariantMap languageFlags READ languageFlags CONSTANT)

  public:
    explicit KeyboardSettingsStore(QObject *parent = nullptr);

    QString currentLanguage() const {
        return m_currentLanguage;
    }
    bool autoCorrectEnabled() const {
        return m_autoCorrectEnabled;
    }
    bool autoCapitalizeEnabled() const {
        return m_autoCapitalizeEnabled;
    }
    bool hapticFeedbackEnabled() const {
        return m_hapticFeedbackEnabled;
    }
    bool predictionsEnabled() const {
        return m_predictionsEnabled;
    }
    QStringList availableLanguages() const {
        return m_availableLanguages;
    }
    QVariantMap languageNames() const {
        return m_languageNames;
    }
    QVariantMap languageFlags() const {
        return m_languageFlags;
    }

    void                setCurrentLanguage(const QString &languageId);
    void                setAutoCorrectEnabled(bool enabled);
    void                setAutoCapitalizeEnabled(bool enabled);
    void                setHapticFeedbackEnabled(bool enabled);
    void                setPredictionsEnabled(bool enabled);

    Q_INVOKABLE QString getLanguageName(const QString &languageId) const;
    Q_INVOKABLE QString getFlag(const QString &languageId) const;

  signals:
    void currentLanguageChanged();
    void autoCorrectEnabledChanged();
    void autoCapitalizeEnabledChanged();
    void hapticFeedbackEnabledChanged();
    void predictionsEnabledChanged();

  private:
    void              resolveSettingsManager();
    QVariant          readSettingValue(const QString &key, const QVariant &fallback) const;
    void              writeSettingValue(const QString &key, const QVariant &value);
    bool              hasProperty(const char *name) const;
    void              connectSettingSignal(const char *signal, const char *slot);

    QPointer<QObject> m_settingsManager;
    QStringList       m_availableLanguages;
    QVariantMap       m_languageNames;
    QVariantMap       m_languageFlags;

    QString           m_currentLanguage       = QStringLiteral("en_US");
    bool              m_autoCorrectEnabled    = true;
    bool              m_autoCapitalizeEnabled = true;
    bool              m_hapticFeedbackEnabled = true;
    bool              m_predictionsEnabled    = true;

  private slots:
    void syncFromSettings();
};
