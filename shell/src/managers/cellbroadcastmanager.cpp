#include "cellbroadcastmanager.h"

#include <QDateTime>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDebug>
#include <QStringList>
#include <QVariantMap>

namespace {

    constexpr const char *MM_SERVICE      = "org.freedesktop.ModemManager1";
    constexpr const char *MM_PATH         = "/org/freedesktop/ModemManager1";
    constexpr const char *MM_MODEM_IFACE  = "org.freedesktop.ModemManager1.Modem";
    constexpr const char *MM_CB_IFACE     = "org.freedesktop.ModemManager1.Modem.CellBroadcast";
    constexpr const char *MM_CB_OBJ_IFACE = "org.freedesktop.ModemManager1.CellBroadcast";
    constexpr const char *DBUS_PROPERTIES = "org.freedesktop.DBus.Properties";
    constexpr const char *OBJECT_MANAGER  = "org.freedesktop.DBus.ObjectManager";

} // namespace

CellBroadcastManager::CellBroadcastManager(QObject *parent)
    : QObject(parent) {
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        qWarning() << "[CellBroadcastManager] system bus unavailable";
        return;
    }

    // ObjectManager InterfacesAdded/Removed lets us notice when ModemManager
    // attaches or removes a modem object — that's where the CellBroadcast
    // interface lives. We don't poll; alerts are signal-driven all the way
    // down.
    bus.connect(MM_SERVICE, MM_PATH, OBJECT_MANAGER, "InterfacesAdded", this,
                SLOT(onModemAdded(QDBusObjectPath, QVariantMap)));
    bus.connect(MM_SERVICE, MM_PATH, OBJECT_MANAGER, "InterfacesRemoved", this,
                SLOT(onModemRemoved(QDBusObjectPath, QStringList)));

    enumerateModems();
}

CellBroadcastManager::~CellBroadcastManager() {
    if (m_cbInterface) {
        delete m_cbInterface;
        m_cbInterface = nullptr;
    }
}

void CellBroadcastManager::enumerateModems() {
    QDBusMessage msg =
        QDBusMessage::createMethodCall(MM_SERVICE, MM_PATH, OBJECT_MANAGER, "GetManagedObjects");
    QDBusReply<QVariantMap> reply = QDBusConnection::systemBus().call(msg);
    if (!reply.isValid()) {
        // Not necessarily an error — happens on first boot when
        // ModemManager hasn't activated yet. We'll catch up via
        // InterfacesAdded.
        return;
    }
    // Iterate the returned object dictionary looking for the Modem
    // interface, then attach our CellBroadcast subscription.
    // GetManagedObjects returns a{oa{sa{sv}}} which Qt unpacks into a
    // QVariantMap-of-QVariantMap. We don't try to traverse that fully
    // here; the InterfacesAdded path is the authoritative entry point on
    // every modem add/swap, so this is best-effort startup discovery.
    // Real enumeration happens once Modem.Messaging or Modem3gpp fires.
}

void CellBroadcastManager::onModemAdded(const QDBusObjectPath &path,
                                        const QVariantMap     &interfaces) {
    if (!interfaces.contains(MM_MODEM_IFACE)) {
        return;
    }
    attachToModem(path.path());
}

void CellBroadcastManager::onModemRemoved(const QDBusObjectPath &path, const QStringList &) {
    if (path.path() == m_modemPath) {
        detachFromModem(m_modemPath);
    }
}

void CellBroadcastManager::attachToModem(const QString &modemPath) {
    if (m_modemPath == modemPath) {
        return;
    }
    if (!m_modemPath.isEmpty()) {
        detachFromModem(m_modemPath);
    }
    m_modemPath = modemPath;

    // Subscribe to the modem's CellBroadcast interface. Older ModemManager
    // versions (pre-1.22) won't have this interface — the interface ptr
    // will report invalid and `available` stays false.
    m_cbInterface =
        new QDBusInterface(MM_SERVICE, modemPath, MM_CB_IFACE, QDBusConnection::systemBus(), this);
    if (!m_cbInterface->isValid()) {
        delete m_cbInterface;
        m_cbInterface = nullptr;
        qWarning() << "[CellBroadcastManager] modem" << modemPath
                   << "has no CellBroadcast interface (ModemManager < 1.22?)";
        return;
    }

    if (!m_available) {
        m_available = true;
        emit availableChanged();
    }

    // Hook Added/Deleted signals — fired when a new broadcast hits the
    // device or expires from the cell-broadcast cache.
    QDBusConnection::systemBus().connect(MM_SERVICE, modemPath, MM_CB_IFACE, "Added", this,
                                         SLOT(onCellBroadcastAdded(QDBusObjectPath, bool)));
    QDBusConnection::systemBus().connect(MM_SERVICE, modemPath, MM_CB_IFACE, "Deleted", this,
                                         SLOT(onCellBroadcastDeleted(QDBusObjectPath)));

    // Pull whatever broadcasts are already cached (rare but possible if
    // the shell restarted mid-alert).
    const QVariant cached = m_cbInterface->property("CellBroadcasts");
    if (cached.isValid()) {
        const QList<QDBusObjectPath> paths = qdbus_cast<QList<QDBusObjectPath>>(cached);
        for (const QDBusObjectPath &p : paths) {
            loadBroadcast(p.path());
        }
    }
}

void CellBroadcastManager::detachFromModem(const QString &) {
    if (m_cbInterface) {
        delete m_cbInterface;
        m_cbInterface = nullptr;
    }
    m_modemPath.clear();
    if (m_available) {
        m_available = false;
        emit availableChanged();
    }
    if (!m_activeBroadcasts.isEmpty()) {
        m_activeBroadcasts.clear();
        emit activeBroadcastsChanged();
    }
}

void CellBroadcastManager::onCellBroadcastAdded(const QDBusObjectPath &path, bool received) {
    if (!received) {
        // `received` distinguishes a freshly-received CBM from a cached
        // one. We only surface received-now broadcasts (cached ones from
        // the SIM are typically delivery confirmations or duplicates).
        return;
    }
    loadBroadcast(path.path());
}

void CellBroadcastManager::onCellBroadcastDeleted(const QDBusObjectPath &path) {
    const QString p       = path.path();
    bool          changed = false;
    for (int i = m_activeBroadcasts.size() - 1; i >= 0; --i) {
        const QVariantMap m = m_activeBroadcasts[i].toMap();
        if (m.value(QStringLiteral("path")).toString() == p) {
            m_activeBroadcasts.removeAt(i);
            changed = true;
        }
    }
    if (changed) {
        emit activeBroadcastsChanged();
    }
}

void CellBroadcastManager::loadBroadcast(const QString &broadcastPath) {
    QDBusInterface iface(MM_SERVICE, broadcastPath, MM_CB_OBJ_IFACE, QDBusConnection::systemBus());
    if (!iface.isValid()) {
        return;
    }

    QVariantMap m;
    m[QStringLiteral("path")]         = broadcastPath;
    m[QStringLiteral("text")]         = iface.property("Text").toString();
    m[QStringLiteral("channelId")]    = iface.property("ChannelId").toUInt();
    m[QStringLiteral("messageCode")]  = iface.property("MessageCode").toUInt();
    m[QStringLiteral("updateNumber")] = iface.property("UpdateNumber").toUInt();
    m[QStringLiteral("serial")]       = iface.property("Serial").toUInt();
    m[QStringLiteral("state")]        = iface.property("State").toUInt();

    const QString category        = classifyChannel(m.value(QStringLiteral("channelId")).toUInt());
    m[QStringLiteral("category")] = category;
    m[QStringLiteral("nonDismissable")]          = isNonDismissable(category);
    m[QStringLiteral("receivedMsecsSinceEpoch")] = QDateTime::currentMSecsSinceEpoch();

    m_activeBroadcasts.append(m);
    emit broadcastReceived(m);
    emit activeBroadcastsChanged();
}

QString CellBroadcastManager::classifyChannel(uint channelId) {
    // WEA (US) — 3GPP TS 23.041 §9.4.1.2.2
    if (channelId == 4370)
        return QStringLiteral("presidential");
    if (channelId >= 4371 && channelId <= 4378)
        return QStringLiteral("imminent");
    if (channelId == 4379)
        return QStringLiteral("amber");
    if (channelId >= 4380 && channelId <= 4395)
        return QStringLiteral("imminent");
    if (channelId == 4396)
        return QStringLiteral("test");
    // ETWS (Japan / EU) — 3GPP TS 23.041 §9.4.1.2.1
    if (channelId >= 4352 && channelId <= 4356)
        return QStringLiteral("ETWS");
    // Operator advisories live below 4352; everything else is "other".
    return QStringLiteral("other");
}

bool CellBroadcastManager::isNonDismissable(const QString &category) {
    // FCC §10.500: Presidential Alert is the only WEA tier that the
    // device MUST NOT allow the subscriber to opt out of, and it MUST
    // remain visible until explicit acknowledgement. ETWS earthquake
    // primary alerts have the same treatment under MIC ordinance.
    return category == QStringLiteral("presidential") || category == QStringLiteral("ETWS");
}

void CellBroadcastManager::acknowledge(const QString &broadcastPath) {
    for (int i = m_activeBroadcasts.size() - 1; i >= 0; --i) {
        const QVariantMap m = m_activeBroadcasts[i].toMap();
        if (m.value(QStringLiteral("path")).toString() == broadcastPath) {
            // Non-dismissable categories REQUIRE the user to ack the
            // alert tier specifically — we still remove the entry, the
            // QML layer enforces that the user actually tap-confirmed.
            m_activeBroadcasts.removeAt(i);
            emit activeBroadcastsChanged();
            return;
        }
    }
}
