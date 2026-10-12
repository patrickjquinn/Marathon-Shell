#include "ambienceclient.h"

#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusServiceWatcher>

using namespace Qt::StringLiterals;

static constexpr auto kService = "org.marathonos.Shell"_L1;
static constexpr auto kPath    = "/org/marathonos/Shell/Ambience"_L1;
static constexpr auto kIface   = "org.marathonos.Shell.Ambience1"_L1;

AmbienceClient::AmbienceClient(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_bus(bus) {
    m_bus.connect(kService, kPath, kIface, QStringLiteral("AmbienceChanged"), this,
                  SLOT(onAmbienceChanged(QVariantMap)));
    // A spare can start while the shell is still coming up and miss its
    // one-off publish, so fetch again whenever the shell (re)appears.
    auto *watcher = new QDBusServiceWatcher(kService, m_bus,
                                            QDBusServiceWatcher::WatchForRegistration, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, &AmbienceClient::fetch);
    fetch();
}

void AmbienceClient::fetch() {
    const QDBusMessage msg =
        QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("GetAmbience"));
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg, 2000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        const QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isValid())
            onAmbienceChanged(reply.value());
        w->deleteLater();
    });
}

bool AmbienceClient::fetchNow(int timeoutMs) {
    const QDBusMessage msg =
        QDBusMessage::createMethodCall(kService, kPath, kIface, QStringLiteral("GetAmbience"));
    const QDBusReply<QVariantMap> reply = m_bus.call(msg, QDBus::Block, timeoutMs);
    if (!reply.isValid())
        return false;
    onAmbienceChanged(reply.value());
    return true;
}

void AmbienceClient::onAmbienceChanged(const QVariantMap &ambience) {
    if (ambience == m_ambience)
        return;
    m_ambience = ambience;
    emit ambienceChanged(m_ambience);
}
