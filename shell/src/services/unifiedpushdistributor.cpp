#include "unifiedpushdistributor.h"

#include "notificationservicecpp.h"
#include "settingsmanager.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDebug>
#include <QSettings>
#include <QStandardPaths>
#include <QUuid>

namespace {
    constexpr const char *kBusName        = "org.unifiedpush.Distributor.marathon";
    constexpr const char *kObjectPath     = "/org/unifiedpush/Distributor";
    constexpr const char *kConnectorPath  = "/org/unifiedpush/Connector";
    constexpr const char *kConnectorIface = "org.unifiedpush.Connector2";
    constexpr const char *kSettingsGroup  = "unifiedpush";

    QString               settingsPath() {
        QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
        return dir + QStringLiteral("/unifiedpush.ini");
    }
} // namespace

UnifiedPushDistributor::UnifiedPushDistributor(NotificationServiceCpp *notificationSink,
                                               SettingsManager *settings, QObject *parent)
    : QObject(parent)
    , m_notificationSink(notificationSink)
    , m_settings(settings) {
    if (m_settings) {
        connect(m_settings, &SettingsManager::unifiedPushFallbackEnabledChanged, this,
                &UnifiedPushDistributor::fallbackNotificationsEnabledChanged);
    }
    load();
    // Replay persisted registrations to whatever backend is listening so it can
    // resume subscriptions without waiting for apps to re-Register on this boot.
    for (auto it = m_registrations.constBegin(); it != m_registrations.constEnd(); ++it) {
        QMetaObject::invokeMethod(
            this,
            [this, token = it.key(), endpoint = it.value().endpoint] {
                emit registrationActive(token, endpoint);
            },
            Qt::QueuedConnection);
    }
}

UnifiedPushDistributor::~UnifiedPushDistributor() {
    if (m_serviceOwned) {
        QDBusConnection::sessionBus().unregisterService(QString::fromLatin1(kBusName));
    }
}

bool UnifiedPushDistributor::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.registerService(QString::fromLatin1(kBusName))) {
        qInfo() << "[UnifiedPushDistributor]" << kBusName
                << "already owned by another distributor; yielding";
        return false;
    }
    m_serviceOwned = true;

    if (!bus.registerObject(QString::fromLatin1(kObjectPath), this,
                            QDBusConnection::ExportAllSlots)) {
        qWarning() << "[UnifiedPushDistributor] registerObject failed:"
                   << bus.lastError().message();
        bus.unregisterService(QString::fromLatin1(kBusName));
        m_serviceOwned = false;
        return false;
    }

    qInfo() << "[UnifiedPushDistributor] Registered" << kBusName << "at" << kObjectPath;
    return true;
}

QVariantMap UnifiedPushDistributor::Register(const QVariantMap &args) {
    const QString service     = args.value(QStringLiteral("service")).toString();
    const QString token       = args.value(QStringLiteral("token")).toString();
    const QString description = args.value(QStringLiteral("description")).toString();

    QVariantMap   out;
    if (service.isEmpty() || token.isEmpty()) {
        out.insert(QStringLiteral("success"), QStringLiteral("INVALID_ARGUMENTS"));
        out.insert(QStringLiteral("reason"), QStringLiteral("service and token are required"));
        return out;
    }

    AppRegistration &reg = m_registrations[token];
    reg.service          = service;
    reg.description      = description;
    persist();

    out.insert(QStringLiteral("success"), QStringLiteral("OK"));

    // Backend hears about every Register, fresh or repeat. It decides whether
    // to mint a new endpoint or reuse a cached one for this token.
    emit registrationActive(token, reg.endpoint);

    // If we already have an endpoint for this token (re-register after restart),
    // notify the connector immediately so the app can resume.
    if (!reg.endpoint.isEmpty()) {
        QVariantMap nep;
        nep.insert(QStringLiteral("token"), token);
        nep.insert(QStringLiteral("endpoint"), reg.endpoint);
        callConnector(service, QStringLiteral("NewEndpoint"), nep);
    }

    qInfo() << "[UnifiedPushDistributor] Register" << service << "token" << token;
    return out;
}

QVariantMap UnifiedPushDistributor::Unregister(const QVariantMap &args) {
    const QString token = args.value(QStringLiteral("token")).toString();
    if (token.isEmpty())
        return {};

    // QHash::take(key) folds find+erase into one call and returns a
    // default-constructed value when the key is absent. Avoids the
    // const_iterator -> erase() UB the previous constFind+erase shape hit.
    const AppRegistration reg = m_registrations.take(token);
    if (reg.service.isEmpty())
        return {};

    const QString service = reg.service;
    persist();
    emit        registrationRemoved(token);

    QVariantMap ureg;
    ureg.insert(QStringLiteral("token"), token);
    callConnector(service, QStringLiteral("Unregistered"), ureg);

    qInfo() << "[UnifiedPushDistributor] Unregister token" << token;
    return {};
}

void UnifiedPushDistributor::deliverEndpoint(const QString &token, const QString &endpoint) {
    const auto it = m_registrations.find(token);
    if (it == m_registrations.end()) {
        qWarning() << "[UnifiedPushDistributor] deliverEndpoint for unknown token" << token;
        return;
    }
    it->endpoint = endpoint;
    persist();

    QVariantMap args;
    args.insert(QStringLiteral("token"), token);
    args.insert(QStringLiteral("endpoint"), endpoint);
    callConnector(it->service, QStringLiteral("NewEndpoint"), args);
}

void UnifiedPushDistributor::deliverMessage(const QString &token, const QByteArray &payload) {
    const auto it = m_registrations.constFind(token);
    if (it == m_registrations.constEnd()) {
        qWarning() << "[UnifiedPushDistributor] deliverMessage for unknown token" << token;
        return;
    }

    QVariantMap args;
    args.insert(QStringLiteral("token"), token);
    args.insert(QStringLiteral("message"), payload);
    args.insert(QStringLiteral("id"), QUuid::createUuid().toString(QUuid::WithoutBraces));
    callConnector(it.value().service, QStringLiteral("Message"), args);

    if (fallbackNotificationsEnabled() && m_notificationSink) {
        // Payloads are opaque (often end-to-end encrypted) so the body is
        // a fixed placeholder; the receiving app is the one with the keys.
        const QString title =
            it.value().description.isEmpty() ? it.value().service : it.value().description;
        QVariantMap opts;
        opts.insert(QStringLiteral("category"), QStringLiteral("push"));
        opts.insert(QStringLiteral("priority"), QStringLiteral("normal"));
        m_notificationSink->sendNotification(it.value().service, title,
                                             QStringLiteral("New push notification"), opts);
    }
}

bool UnifiedPushDistributor::fallbackNotificationsEnabled() const {
    return m_settings && m_settings->unifiedPushFallbackEnabled();
}

void UnifiedPushDistributor::setFallbackNotificationsEnabled(bool enabled) {
    if (!m_settings)
        return;
    m_settings->setUnifiedPushFallbackEnabled(enabled);
}

void UnifiedPushDistributor::callConnector(const QString &serviceBus, const QString &method,
                                           const QVariantMap &args) {
    // QDBusInterface::isValid() introspects the peer synchronously on
    // construction; if that introspect roundtrip races or the peer's
    // introspection xml omits the iface we want, the check fails false
    // and the call gets skipped even though createCall() + asyncCall()
    // would deliver. Build the message directly to skip the introspect.
    QDBusMessage msg =
        QDBusMessage::createMethodCall(serviceBus, QString::fromLatin1(kConnectorPath),
                                       QString::fromLatin1(kConnectorIface), method);
    msg.setArguments({QVariant::fromValue(args)});
    QDBusConnection::sessionBus().asyncCall(msg);
}

void UnifiedPushDistributor::persist() const {
    QSettings s(settingsPath(), QSettings::IniFormat);
    s.beginGroup(QString::fromLatin1(kSettingsGroup));
    s.remove(QString()); // wipe stale token entries before rewriting
    s.beginWriteArray(QStringLiteral("registrations"), m_registrations.size());
    int i = 0;
    for (auto it = m_registrations.constBegin(); it != m_registrations.constEnd(); ++it, ++i) {
        s.setArrayIndex(i);
        s.setValue(QStringLiteral("token"), it.key());
        s.setValue(QStringLiteral("service"), it.value().service);
        s.setValue(QStringLiteral("description"), it.value().description);
        s.setValue(QStringLiteral("endpoint"), it.value().endpoint);
    }
    s.endArray();
    s.endGroup();
}

void UnifiedPushDistributor::load() {
    QSettings s(settingsPath(), QSettings::IniFormat);
    s.beginGroup(QString::fromLatin1(kSettingsGroup));
    const int n = s.beginReadArray(QStringLiteral("registrations"));
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        const QString token = s.value(QStringLiteral("token")).toString();
        if (token.isEmpty())
            continue;
        AppRegistration reg;
        reg.service            = s.value(QStringLiteral("service")).toString();
        reg.description        = s.value(QStringLiteral("description")).toString();
        reg.endpoint           = s.value(QStringLiteral("endpoint")).toString();
        m_registrations[token] = reg;
    }
    s.endArray();
    s.endGroup();
}
