#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QVariantMap>
#include <QtQmlIntegration/qqmlintegration.h>

#include <functional>

class QDBusMessage;
class QQmlEngine;
class QJSEngine;

// mmsd-tng's carrier settings (org.ofono.mms.ModemManager on /org/ofono/mms):
// MMSC, MMS proxy, MMS APN and whether incoming MMS download on their own.
// Values are as mmsd-tng keeps them, its placeholders included.
class MmsSettings : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY changed)
    Q_PROPERTY(bool loaded READ loaded NOTIFY changed)
    Q_PROPERTY(QString mmsc READ mmsc NOTIFY changed)
    Q_PROPERTY(QString apn READ apn NOTIFY changed)
    Q_PROPERTY(QString proxy READ proxy NOTIFY changed)
    Q_PROPERTY(bool autoDownload READ autoDownload NOTIFY changed)

  public:
    static MmsSettings *create(QQmlEngine *engine, QJSEngine *);
    explicit MmsSettings(QObject *parent = nullptr);

    bool    available() const { return m_available; }
    bool    loaded() const { return m_loaded; }
    QString mmsc() const { return m_settings.value(QStringLiteral("CarrierMMSC")).toString(); }
    QString apn() const { return m_settings.value(QStringLiteral("MMS_APN")).toString(); }
    QString proxy() const { return m_settings.value(QStringLiteral("CarrierMMSProxy")).toString(); }
    bool    autoDownload() const { return m_settings.value(QStringLiteral("AutoProcessSMSWAP"), true).toBool(); }

    Q_INVOKABLE void refresh();
    // An empty proxy is none.
    Q_INVOKABLE void save(const QString &mmsc, const QString &apn, const QString &proxy);
    Q_INVOKABLE void setAutoDownload(bool on);

  Q_SIGNALS:
    void changed();
    void saved();
    void failed(const QString &error);

  private Q_SLOTS:
    void onSettingsChanged(const QString &apn, const QString &mmsc, const QString &proxy);

  private:
    void call(const QString &method, const QVariantList &args, std::function<void(const QDBusMessage &)> done);

    QDBusConnection m_bus;
    bool            m_available = false;
    bool            m_loaded    = false;
    QVariantMap     m_settings;
};
