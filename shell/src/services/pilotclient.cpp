#include "pilotclient.h"

#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QQmlEngine>

namespace {

// NOLINTBEGIN(bugprone-throwing-static-initialization) QStringLiteral never allocates
const QString kPath  = QStringLiteral("/org/shipwright/Pilot");
const QString kIface = QStringLiteral("org.shipwright.Pilot1");
// NOLINTEND(bugprone-throwing-static-initialization)

QDBusMessage busCall(const QString &method) {
    return QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"),
        QStringLiteral("org.freedesktop.DBus"), method);
}

} // namespace

const QString &PilotClient::serviceName() {
    static const QString kName = QStringLiteral("org.shipwright.Pilot");
    return kName;
}

PilotClient *PilotClient::create(QQmlEngine *engine, QJSEngine *) {
    auto *client = new PilotClient(QDBusConnection::sessionBus(), engine);
    QQmlEngine::setObjectOwnership(client, QQmlEngine::CppOwnership);
    return client;
}

PilotClient::PilotClient(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_bus(bus) {
    m_poll.setInterval(30000);
    connect(&m_poll, &QTimer::timeout, this, &PilotClient::check);
    auto *watcher = new QDBusServiceWatcher(serviceName(), m_bus,
                                            QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &PilotClient::check);
    check();
}

void PilotClient::setWatching(bool watching) {
    if (watching == m_poll.isActive())
        return;
    if (watching) {
        m_poll.start();
        check();
    } else {
        m_poll.stop();
    }
    emit watchingChanged();
}

void PilotClient::check() {
    auto *activatable = new QDBusPendingCallWatcher(
        m_bus.asyncCall(busCall(QStringLiteral("ListActivatableNames"))), this);
    connect(activatable, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                const QDBusPendingReply<QStringList> names = *call;
                if (!names.isError() && names.value().contains(serviceName())) {
                    setAvailable(true);
                    return;
                }
                // Running without a service file (a developer's pilotd).
                QDBusMessage owner = busCall(QStringLiteral("NameHasOwner"));
                owner << serviceName();
                auto *running = new QDBusPendingCallWatcher(m_bus.asyncCall(owner), this);
                connect(running, &QDBusPendingCallWatcher::finished, this,
                        [this](QDBusPendingCallWatcher *call) {
                            call->deleteLater();
                            const QDBusPendingReply<bool> has = *call;
                            setAvailable(!has.isError() && has.value());
                        });
            });
}

void PilotClient::showSheetFor(uint pid) {
    QDBusMessage msg =
        QDBusMessage::createMethodCall(serviceName(), kPath, kIface, QStringLiteral("ShowSheetFor"));
    msg << pid;
    // Activating pilotd and reading the app on screen can take seconds.
    auto *call = new QDBusPendingCallWatcher(m_bus.asyncCall(msg, 25000), this);
    connect(call, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        if (!call->isError())
            return;
        qInfo() << "[Pilot] ShowSheetFor:" << call->error().name();
        if (call->error().type() == QDBusError::UnknownMethod)
            m_bus.asyncCall(QDBusMessage::createMethodCall(serviceName(), kPath, kIface,
                                                           QStringLiteral("ShowSheet")));
    });
}

void PilotClient::setAvailable(bool available) {
    if (available == m_available)
        return;
    m_available = available;
    emit availableChanged();
}
