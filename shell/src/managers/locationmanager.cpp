#include "locationmanager.h"
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusReply>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDebug>

QDBusArgument &operator<<(QDBusArgument &argument, const GeoClueTimestamp &ts) {
    argument.beginStructure();
    argument << ts.seconds << ts.microseconds;
    argument.endStructure();
    return argument;
}

// Qt-DBus mandates this exact signature so operator chaining (arg >> a >> b)
// works; the returned reference is always to QDBus's stable internal arg,
// never a temporary.
const QDBusArgument &operator>>(const QDBusArgument &argument, GeoClueTimestamp &ts) {
    argument.beginStructure();
    argument >> ts.seconds >> ts.microseconds;
    argument.endStructure();
    return argument; // NOLINT(bugprone-return-const-ref-from-parameter)
}

static const QString kGeoclue = QStringLiteral("org.freedesktop.GeoClue2");

// Every GeoClue call is async: the service is bus-activated and, with no
// Wi-Fi or SIM, takes up to 90 s to come up. A QDBusInterface would
// introspect it synchronously and freeze the shell for the D-Bus timeout.
static QDBusPendingCall geoclueCall(const QString &path, const QString &iface,
                                    const QString &method, const QVariantList &args = {}) {
    QDBusMessage msg = QDBusMessage::createMethodCall(kGeoclue, path, iface, method);
    msg.setArguments(args);
    return QDBusConnection::systemBus().asyncCall(msg);
}

LocationManager::LocationManager(QObject *parent)
    : QObject(parent)
    , m_available(false)
    , m_active(false)
    , m_latitude(0.0)
    , m_longitude(0.0)
    , m_accuracy(0.0)
    , m_altitude(0.0)
    , m_speed(0.0)
    , m_heading(0.0)
    , m_timestamp(0) {
    qRegisterMetaType<GeoClueTimestamp>("GeoClueTimestamp");
    qDBusRegisterMetaType<GeoClueTimestamp>();

    connectToGeoclue();
}

LocationManager::~LocationManager() {
    if (m_active) {
        stop();
    }
}

void LocationManager::connectToGeoclue() {
    auto *bus = QDBusConnection::systemBus().interface();
    m_available = bus && (bus->isServiceRegistered(kGeoclue).value() ||
                          bus->activatableServiceNames().value().contains(kGeoclue));
    emit availableChanged();
    if (!m_available) {
        qDebug() << "[LocationManager] Geoclue2 not available";
        return;
    }
    m_startWanted = true;
    createClient();
}

void LocationManager::createClient() {
    if (!m_available || m_creatingClient || !m_clientPath.isEmpty())
        return;
    m_creatingClient = true;

    auto *watcher = new QDBusPendingCallWatcher(
        geoclueCall("/org/freedesktop/GeoClue2/Manager", "org.freedesktop.GeoClue2.Manager",
                    "GetClient"),
        this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                m_creatingClient = false;
                QDBusPendingReply<QDBusObjectPath> reply = *call;
                if (reply.isError()) {
                    qWarning() << "[LocationManager] Failed to create client:"
                               << reply.error().message();
                    emit error("Failed to create location client");
                    return;
                }
                m_clientPath = reply.value().path();

                const QString props = QStringLiteral("org.freedesktop.DBus.Properties");
                const QString client = QStringLiteral("org.freedesktop.GeoClue2.Client");
                geoclueCall(m_clientPath, props, "Set",
                            {client, QStringLiteral("DesktopId"),
                             QVariant::fromValue(QDBusVariant(QStringLiteral("org.marathon.Shell")))});
                geoclueCall(m_clientPath, props, "Set",
                            {client, QStringLiteral("RequestedAccuracyLevel"),
                             QVariant::fromValue(QDBusVariant(8u))});
                QDBusConnection::systemBus().connect(
                    kGeoclue, m_clientPath, client, "LocationUpdated", this,
                    SLOT(onLocationUpdated(QDBusObjectPath, QDBusObjectPath)));

                if (m_startWanted)
                    start();
            });
}

void LocationManager::start() {
    if (m_active)
        return;
    m_startWanted = true;
    if (m_clientPath.isEmpty()) {
        createClient();
        return;
    }

    auto *watcher = new QDBusPendingCallWatcher(
        geoclueCall(m_clientPath, "org.freedesktop.GeoClue2.Client", "Start"), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                QDBusPendingReply<void> reply = *call;
                if (reply.isError()) {
                    qWarning() << "[LocationManager] Failed to start:" << reply.error().message();
                    emit error("Failed to start location updates");
                    return;
                }
                m_active = true;
                emit activeChanged();
            });
}

void LocationManager::stop() {
    m_startWanted = false;
    if (m_clientPath.isEmpty() || !m_active)
        return;

    geoclueCall(m_clientPath, "org.freedesktop.GeoClue2.Client", "Stop");
    m_active = false;
    emit activeChanged();
}

void LocationManager::onLocationUpdated(const QDBusObjectPath &oldLocation,
                                        const QDBusObjectPath &newLocation) {
    Q_UNUSED(oldLocation)

    QString locationPath = newLocation.path();
    qDebug() << "[LocationManager] Location updated:" << locationPath;

    updateLocation(locationPath);
}

void LocationManager::updateLocation(const QString &locationPath) {
    QDBusInterface location("org.freedesktop.GeoClue2", locationPath,
                            "org.freedesktop.GeoClue2.Location", QDBusConnection::systemBus());

    if (!location.isValid()) {
        qWarning() << "[LocationManager] Location interface invalid";
        return;
    }

    m_latitude  = location.property("Latitude").toDouble();
    m_longitude = location.property("Longitude").toDouble();
    m_accuracy  = location.property("Accuracy").toDouble();
    m_altitude  = location.property("Altitude").toDouble();
    m_speed     = location.property("Speed").toDouble();
    m_heading   = location.property("Heading").toDouble();

    QDBusInterface       props("org.freedesktop.GeoClue2", location.path(),
                               "org.freedesktop.DBus.Properties", QDBusConnection::systemBus());

    QDBusReply<QVariant> reply =
        props.call("Get", "org.freedesktop.GeoClue2.Location", "Timestamp");
    if (reply.isValid()) {
        QVariant val = reply.value();
        if (val.userType() == qMetaTypeId<QDBusArgument>()) {
            const QDBusArgument &arg = val.value<QDBusArgument>();
            GeoClueTimestamp     ts;
            arg >> ts;
            m_timestamp = (ts.seconds * 1000) + (ts.microseconds / 1000);
        } else if (val.canConvert<GeoClueTimestamp>()) {
            GeoClueTimestamp ts = val.value<GeoClueTimestamp>();
            m_timestamp         = (ts.seconds * 1000) + (ts.microseconds / 1000);
        }
    } else {
        qWarning() << "[LocationManager] Failed to read Timestamp:" << reply.error().message();
    }

    emit locationChanged();

    qInfo() << "[LocationManager] Location:" << m_latitude << "," << m_longitude
            << "accuracy:" << m_accuracy << "m";
}
