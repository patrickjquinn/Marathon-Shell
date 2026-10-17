#include "geoclueagent.h"

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QDebug>

namespace {

    const QString kService = QStringLiteral("org.freedesktop.GeoClue2");
    constexpr uint kAccuracyExact = 8;

} // namespace

const QString &GeoClueAgent::agentId() {
    static const QString kId = QStringLiteral("marathon-shell");
    return kId;
}

GeoClueAgent::GeoClueAgent(const QDBusConnection &bus, Authorizer authorize, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
    , m_authorize(std::move(authorize)) {
    if (!m_bus.registerObject(QStringLiteral("/org/freedesktop/GeoClue2/Agent"), this,
                              QDBusConnection::ExportAllSlots |
                                  QDBusConnection::ExportAllProperties)) {
        qWarning() << "[GeoClueAgent] Cannot export the agent:" << m_bus.lastError().message();
        return;
    }
    auto *watcher = new QDBusServiceWatcher(kService, m_bus,
                                            QDBusServiceWatcher::WatchForRegistration, this);
    connect(watcher, &QDBusServiceWatcher::serviceRegistered, this, &GeoClueAgent::addAgent);
    // Registering now would start GeoClue just to idle; it starts with its first client.
    if (m_bus.interface() && m_bus.interface()->isServiceRegistered(kService))
        addAgent();
}

uint GeoClueAgent::maxAccuracyLevel() const {
    return kAccuracyExact;
}

bool GeoClueAgent::AuthorizeApp(const QString &desktopId, uint requestedAccuracy,
                                uint &allowedAccuracy) {
    const bool authorized = m_authorize(desktopId);
    allowedAccuracy       = authorized ? qMin(requestedAccuracy, kAccuracyExact) : 0;
    if (!authorized)
        qWarning() << "[GeoClueAgent] Refused location to" << desktopId;
    return authorized;
}

void GeoClueAgent::addAgent() {
    QDBusMessage msg = QDBusMessage::createMethodCall(
        kService, QStringLiteral("/org/freedesktop/GeoClue2/Manager"),
        QStringLiteral("org.freedesktop.GeoClue2.Manager"), QStringLiteral("AddAgent"));
    msg << agentId();
    auto *call = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        w->deleteLater();
        if (w->isError()) {
            qWarning() << "[GeoClueAgent] AddAgent:" << w->error().message();
            return;
        }
        emit registered();
    });
}
