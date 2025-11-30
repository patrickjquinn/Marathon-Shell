#include "locationmanager.h"
#include <QDBusConnection>
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

const QDBusArgument &operator>>(const QDBusArgument &argument, GeoClueTimestamp &ts) {
    argument.beginStructure();
    argument >> ts.seconds >> ts.microseconds;
    argument.endStructure();
    return argument;
}

LocationManager::LocationManager(QObject *parent)
    : QObject(parent)
    , m_manager(nullptr)
    , m_client(nullptr)
    , m_available(false)
    , m_active(false)
    , m_latitude(0.0)
    , m_longitude(0.0)
    , m_accuracy(0.0)
    , m_altitude(0.0)
    , m_speed(0.0)
    , m_heading(0.0)
    , m_timestamp(0) {
    qDebug() << "[LocationManager] Initializing";

    // Register custom D-Bus type for GeoClue2 Timestamp
    qRegisterMetaType<GeoClueTimestamp>("GeoClueTimestamp");
    qDBusRegisterMetaType<GeoClueTimestamp>();

    connectToGeoclue();
}

LocationManager::~LocationManager() {
    if (m_active) {
        stop();
    }
    if (m_client) {
        delete m_client;
    }
    if (m_manager) {
        delete m_manager;
    }
}

void LocationManager::connectToGeoclue() {
    qDebug() << "[LocationManager] Connecting to Geoclue2";

    m_manager =
        new QDBusInterface("org.freedesktop.GeoClue2", "/org/freedesktop/GeoClue2/Manager",
                           "org.freedesktop.GeoClue2.Manager", QDBusConnection::systemBus(), this);

    if (!m_manager->isValid()) {
        qDebug() << "[LocationManager] Geoclue2 not available:" << m_manager->lastError().message();
        m_available = false;
        emit availableChanged();
        return;
    }

    qInfo() << "[LocationManager] ✓ Connected to Geoclue2";
    m_available = true;
    emit availableChanged();

    createClient();
}

void LocationManager::createClient() {
    if (!m_manager || !m_manager->isValid()) {
        return;
    }

    qDebug() << "[LocationManager] Creating client asynchronously...";

    // Create client asynchronously
    QDBusPendingCall         asyncCall = m_manager->asyncCall("GetClient");
    QDBusPendingCallWatcher *watcher   = new QDBusPendingCallWatcher(asyncCall, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                QDBusPendingReply<QDBusObjectPath> reply = *call;
                if (reply.isError()) {
                    qWarning() << "[LocationManager] Failed to create client:"
                               << reply.error().message();
                    emit error("Failed to create location client");
                } else {
                    m_clientPath = reply.value().path();
                    qDebug() << "[LocationManager] Client created:" << m_clientPath;

                    m_client = new QDBusInterface("org.freedesktop.GeoClue2", m_clientPath,
                                                  "org.freedesktop.GeoClue2.Client",
                                                  QDBusConnection::systemBus(), this);

                    if (!m_client->isValid()) {
                        qWarning() << "[LocationManager] Client interface invalid";
                    } else {
                        // Set desktop ID
                        m_client->setProperty("DesktopId", "org.marathon.Shell");

                        // Request high accuracy
                        m_client->setProperty("RequestedAccuracyLevel", 8); // EXACT (GPS)

                        // Monitor location updates
                        QDBusConnection::systemBus().connect(
                            "org.freedesktop.GeoClue2", m_clientPath,
                            "org.freedesktop.GeoClue2.Client", "LocationUpdated", this,
                            SLOT(onLocationUpdated(QDBusObjectPath, QDBusObjectPath)));

                        qInfo() << "[LocationManager] Client configured and ready";

                        // Auto-start if requested or implied
                        start();
                    }
                }
                call->deleteLater();
            });
}

void LocationManager::start() {
    if (!m_client || !m_client->isValid() || m_active) {
        return;
    }

    qInfo() << "[LocationManager] Starting location updates";

    QDBusPendingCall         asyncCall = m_client->asyncCall("Start");
    QDBusPendingCallWatcher *watcher   = new QDBusPendingCallWatcher(asyncCall, this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                QDBusPendingReply<void> reply = *call;
                if (reply.isError()) {
                    qWarning() << "[LocationManager] Failed to start:" << reply.error().message();
                    emit error("Failed to start location updates");
                } else {
                    m_active = true;
                    emit activeChanged();
                    qInfo() << "[LocationManager] ✓ Location updates started";
                }
                call->deleteLater();
            });
}

void LocationManager::stop() {
    if (!m_client || !m_client->isValid() || !m_active) {
        return;
    }

    qInfo() << "[LocationManager] Stopping location updates";

    // We don't strictly need to wait for Stop to finish, but using asyncCall prevents blocking
    m_client->asyncCall("Stop");
    m_active = false;
    emit activeChanged();

    qInfo() << "[LocationManager] Location updates stopped";
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

    // Get location properties
    m_latitude  = location.property("Latitude").toDouble();
    m_longitude = location.property("Longitude").toDouble();
    m_accuracy  = location.property("Accuracy").toDouble();
    m_altitude  = location.property("Altitude").toDouble();
    m_speed     = location.property("Speed").toDouble();
    m_heading   = location.property("Heading").toDouble();

    // Timestamp is (seconds, microseconds) - (tt)
    // We use the Properties interface directly to avoid QDBusAbstractInterface property() issues with custom types
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

    qInfo() << "[LocationManager] ✓ Location:" << m_latitude << "," << m_longitude
            << "accuracy:" << m_accuracy << "m";
}
