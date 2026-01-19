#include "KeyboardSettingsStore.h"

#include <QMetaMethod>
#include <QMetaProperty>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTimer>

KeyboardSettingsStore::KeyboardSettingsStore(QObject *parent)
    : QObject(parent)
    , m_availableLanguages({"en_US", "fr_FR", "de_DE", "es_ES", "pt_BR", "it_IT", "ru_RU", "ar_SA",
                            "zh_CN", "ja_JP"})
    , m_languageNames({{"en_US", "English (US)"},
                       {"fr_FR", "Français"},
                       {"de_DE", "Deutsch"},
                       {"es_ES", "Español"},
                       {"pt_BR", "Português"},
                       {"it_IT", "Italiano"},
                       {"ru_RU", "Русский"},
                       {"ar_SA", "العربية"},
                       {"zh_CN", "中文"},
                       {"ja_JP", "日本語"}})
    , m_languageFlags({{"en_US", "🇺🇸"},
                       {"fr_FR", "🇫🇷"},
                       {"de_DE", "🇩🇪"},
                       {"es_ES", "🇪🇸"},
                       {"pt_BR", "🇧🇷"},
                       {"it_IT", "🇮🇹"},
                       {"ru_RU", "🇷🇺"},
                       {"ar_SA", "🇸🇦"},
                       {"zh_CN", "🇨🇳"},
                       {"ja_JP", "🇯🇵"}}) {
    QTimer::singleShot(0, this, &KeyboardSettingsStore::resolveSettingsManager);
}

void KeyboardSettingsStore::setCurrentLanguage(const QString &languageId) {
    if (m_currentLanguage == languageId) {
        return;
    }
    m_currentLanguage = languageId;
    emit currentLanguageChanged();
    writeSettingValue("keyboardLanguage", languageId);
}

void KeyboardSettingsStore::setAutoCorrectEnabled(bool enabled) {
    if (m_autoCorrectEnabled == enabled) {
        return;
    }
    m_autoCorrectEnabled = enabled;
    emit autoCorrectEnabledChanged();
    writeSettingValue("keyboardAutoCorrection", enabled);
}

void KeyboardSettingsStore::setAutoCapitalizeEnabled(bool enabled) {
    if (m_autoCapitalizeEnabled == enabled) {
        return;
    }
    m_autoCapitalizeEnabled = enabled;
    emit autoCapitalizeEnabledChanged();
    writeSettingValue("keyboardAutoCapitalize", enabled);
}

void KeyboardSettingsStore::setHapticFeedbackEnabled(bool enabled) {
    if (m_hapticFeedbackEnabled == enabled) {
        return;
    }
    m_hapticFeedbackEnabled = enabled;
    emit hapticFeedbackEnabledChanged();
    writeSettingValue("keyboardHapticStrength",
                      enabled ? QStringLiteral("medium") : QStringLiteral("off"));
}

void KeyboardSettingsStore::setPredictionsEnabled(bool enabled) {
    if (m_predictionsEnabled == enabled) {
        return;
    }
    m_predictionsEnabled = enabled;
    emit predictionsEnabledChanged();
    writeSettingValue("keyboardPredictiveText", enabled);
}

QString KeyboardSettingsStore::getLanguageName(const QString &languageId) const {
    const QVariant value = m_languageNames.value(languageId);
    return value.isValid() ? value.toString() : languageId;
}

QString KeyboardSettingsStore::getFlag(const QString &languageId) const {
    const QVariant value = m_languageFlags.value(languageId);
    return value.isValid() ? value.toString() : QStringLiteral("🌐");
}

void KeyboardSettingsStore::resolveSettingsManager() {
    if (m_settingsManager) {
        return;
    }
    QQmlEngine *engine = qmlEngine(this);
    if (!engine) {
        return;
    }
    QObject *settingsObject =
        engine->rootContext()->contextProperty("SettingsManagerCpp").value<QObject *>();
    if (!settingsObject) {
        return;
    }
    m_settingsManager = settingsObject;
    connectSettingSignal("keyboardLanguageChanged()", SLOT(syncFromSettings()));
    connectSettingSignal("keyboardAutoCorrectionChanged()", SLOT(syncFromSettings()));
    connectSettingSignal("keyboardAutoCapitalizeChanged()", SLOT(syncFromSettings()));
    connectSettingSignal("keyboardPredictiveTextChanged()", SLOT(syncFromSettings()));
    connectSettingSignal("keyboardHapticStrengthChanged()", SLOT(syncFromSettings()));
    syncFromSettings();
}

void KeyboardSettingsStore::syncFromSettings() {
    const QString language = readSettingValue("keyboardLanguage", "en_US").toString();
    if (m_currentLanguage != language) {
        m_currentLanguage = language;
        emit currentLanguageChanged();
    }

    const bool autoCorrect = readSettingValue("keyboardAutoCorrection", true).toBool();
    if (m_autoCorrectEnabled != autoCorrect) {
        m_autoCorrectEnabled = autoCorrect;
        emit autoCorrectEnabledChanged();
    }

    const bool autoCapitalize = readSettingValue("keyboardAutoCapitalize", true).toBool();
    if (m_autoCapitalizeEnabled != autoCapitalize) {
        m_autoCapitalizeEnabled = autoCapitalize;
        emit autoCapitalizeEnabledChanged();
    }

    const bool predictions = readSettingValue("keyboardPredictiveText", true).toBool();
    if (m_predictionsEnabled != predictions) {
        m_predictionsEnabled = predictions;
        emit predictionsEnabledChanged();
    }

    const QString hapticStrength =
        readSettingValue("keyboardHapticStrength", QStringLiteral("medium")).toString();
    const bool hapticEnabled = hapticStrength != QStringLiteral("off");
    if (m_hapticFeedbackEnabled != hapticEnabled) {
        m_hapticFeedbackEnabled = hapticEnabled;
        emit hapticFeedbackEnabledChanged();
    }
}

QVariant KeyboardSettingsStore::readSettingValue(const QString  &key,
                                                 const QVariant &fallback) const {
    if (!m_settingsManager) {
        return fallback;
    }
    if (hasProperty(key.toUtf8().constData())) {
        const QVariant value = m_settingsManager->property(key.toUtf8().constData());
        return value.isValid() ? value : fallback;
    }
    QVariant value = fallback;
    QMetaObject::invokeMethod(m_settingsManager, "get", Q_RETURN_ARG(QVariant, value),
                              Q_ARG(QString, key), Q_ARG(QVariant, fallback));
    return value;
}

void KeyboardSettingsStore::writeSettingValue(const QString &key, const QVariant &value) {
    if (!m_settingsManager) {
        return;
    }
    if (hasProperty(key.toUtf8().constData())) {
        m_settingsManager->setProperty(key.toUtf8().constData(), value);
        return;
    }
    QMetaObject::invokeMethod(m_settingsManager, "set", Q_ARG(QString, key),
                              Q_ARG(QVariant, value));
}

bool KeyboardSettingsStore::hasProperty(const char *name) const {
    if (!m_settingsManager) {
        return false;
    }
    return m_settingsManager->metaObject()->indexOfProperty(name) != -1;
}

void KeyboardSettingsStore::connectSettingSignal(const char *signal, const char *slot) {
    if (!m_settingsManager) {
        return;
    }
    const QMetaObject *meta = m_settingsManager->metaObject();
    if (meta->indexOfSignal(signal) == -1) {
        return;
    }
    QMetaObject::connect(m_settingsManager, meta->indexOfSignal(signal), this,
                         this->metaObject()->indexOfSlot(slot));
}
