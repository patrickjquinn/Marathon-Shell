#include "MmsSettings.h"

#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusVariant>
#include <QQmlEngine>

namespace {
    const QString kService   = QStringLiteral("org.ofono.mms");
    const QString kPath      = QStringLiteral("/org/ofono/mms");
    const QString kInterface = QStringLiteral("org.ofono.mms.ModemManager");
} // namespace

MmsSettings *MmsSettings::create(QQmlEngine *engine, QJSEngine *) {
    auto *settings = new MmsSettings(engine);
    QQmlEngine::setObjectOwnership(settings, QQmlEngine::CppOwnership);
    return settings;
}

MmsSettings::MmsSettings(QObject *parent)
    : QObject(parent)
    , m_bus(QDBusConnection::sessionBus()) {
    m_bus.connect(kService, kPath, kInterface, QStringLiteral("SettingsChanged"), this,
                  SLOT(onSettingsChanged(QString, QString, QString)));
    refresh();
}

void MmsSettings::call(const QString &method, const QVariantList &args,
                       std::function<void(const QDBusMessage &)> done) {
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, kInterface, method);
    m.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(m, 10000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, done = std::move(done)] {
        watcher->deleteLater();
        done(watcher->reply());
    });
}

// mmsd-tng is bus-activated: no reply means no MMS service on this device.
void MmsSettings::refresh() {
    call(QStringLiteral("ViewSettings"), {}, [this](const QDBusMessage &r) {
        const bool ok = r.type() == QDBusMessage::ReplyMessage && !r.arguments().isEmpty();
        m_available = ok;
        m_loaded    = true;
        m_settings  = ok ? qdbus_cast<QVariantMap>(r.arguments().constFirst()) : QVariantMap();
        Q_EMIT changed();
    });
}

void MmsSettings::save(const QString &mmsc, const QString &apn, const QString &proxy) {
    const QVariantMap all{{QStringLiteral("CarrierMMSC"), mmsc},
                          {QStringLiteral("MMS_APN"), apn},
                          {QStringLiteral("CarrierMMSProxy"), proxy.isEmpty() ? QStringLiteral("NULL") : proxy}};
    call(QStringLiteral("ChangeAllSettings"), {all}, [this](const QDBusMessage &r) {
        if (r.type() != QDBusMessage::ReplyMessage) {
            Q_EMIT failed(r.errorMessage());
            return;
        }
        // Messages already waiting use the new settings only once the queue runs again.
        call(QStringLiteral("ProcessMessageQueue"), {}, [](const QDBusMessage &) {});
        refresh();
        Q_EMIT saved();
    });
}

void MmsSettings::setAutoDownload(bool on) {
    call(QStringLiteral("ChangeSettings"), {QStringLiteral("AutoProcessSMSWAP"), QVariant::fromValue(QDBusVariant(on))},
         [this](const QDBusMessage &r) {
             if (r.type() != QDBusMessage::ReplyMessage)
                 Q_EMIT failed(r.errorMessage());
             refresh();
         });
}

void MmsSettings::onSettingsChanged(const QString &, const QString &, const QString &) {
    refresh();
}
