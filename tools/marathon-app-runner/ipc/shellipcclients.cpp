#include "shellipcclients.h"
#include "marathon-app-native/src/audio.cxxqt.h"
#include "marathon-app-native/src/display.cxxqt.h"
#include "marathon-app-native/src/network.cxxqt.h"
#include "marathon-app-native/src/settings.cxxqt.h"
#include "marathon-app-native/src/power.cxxqt.h"
#include "dbusnormalize.h"
#include "marathonmanifest.h"

#include <ctime>

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>
#include <vector>
#include <unistd.h>
#include <QStandardPaths>
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QDBusUnixFileDescriptor>
#include <QDBusMetaType>
#include <algorithm>
#include <cmath>
#include <utility>   // std::as_const

static bool isAccessDenied(const QDBusError &e) {
    return e.type() == QDBusError::AccessDenied;
}

static bool debugEnabled() {
    const QByteArray v = qgetenv("MARATHON_DEBUG").trimmed().toLower();
    return v == "1" || v == "true";
}

static QDBusInterface makePermissionsIface(QObject *parent) {
    return QDBusInterface("org.marathonos.Shell", "/org/marathonos/Shell/Permissions",
                          "org.marathonos.Shell.Permissions1", QDBusConnection::sessionBus(),
                          parent);
}

static void connectPermissionGranted(QObject *receiver) {
    QDBusConnection::sessionBus().connect("org.marathonos.Shell",
                                          "/org/marathonos/Shell/Permissions",
                                          "org.marathonos.Shell.Permissions1", "PermissionGranted",
                                          receiver, SLOT(onPermissionGranted(QString, QString)));
}

static QString notificationServiceName() {
    auto *iface = QDBusConnection::sessionBus().interface();
    if (iface && iface->isServiceRegistered("org.marathon.Notifications"))
        return QStringLiteral("org.marathon.Notifications");
    return QStringLiteral("org.freedesktop.Notifications");
}

CallHistoryClient::CallHistoryClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/CallHistory",
              "org.marathonos.Shell.CallHistory1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid()) {
        qWarning() << "[CallHistoryClient] DBus interface invalid:"
                   << m_iface.lastError().message();
        return;
    }
    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/CallHistory",
        "org.marathonos.Shell.CallHistory1", "HistoryChanged", this, SLOT(refresh()));
    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/CallHistory",
        "org.marathonos.Shell.CallHistory1", "CallAdded", this, SIGNAL(callAdded(int)));
    refresh();
}

void CallHistoryClient::setHistory(const QVariantList &v) {
    m_history = normalizeListDeep(v);
    emit historyChanged();
}

void CallHistoryClient::refresh() {
    QDBusReply<QVariantList> r = m_iface.call("GetHistory");
    if (!r.isValid()) {
        if (r.error().type() != QDBusError::AccessDenied)
            qWarning() << "[CallHistoryClient] GetHistory failed:" << r.error().message();
        return;
    }
    setHistory(r.value());
}

void CallHistoryClient::addCall(const QString &number, const QString &type, qint64 timestamp,
                                int duration) {
    auto r = m_iface.call("AddCall", number, type, timestamp, duration);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[CallHistoryClient] AddCall failed:" << r.errorMessage();
}

void CallHistoryClient::deleteCall(int id) {
    auto r = m_iface.call("DeleteCall", id);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[CallHistoryClient] DeleteCall failed:" << r.errorMessage();
}

void CallHistoryClient::clearHistory() {
    auto r = m_iface.call("ClearHistory");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[CallHistoryClient] ClearHistory failed:" << r.errorMessage();
}

QVariantMap CallHistoryClient::getCallById(int id) {
    QDBusReply<QVariantMap> r = m_iface.call("GetCallById", id);
    if (!r.isValid()) {
        qWarning() << "[CallHistoryClient] GetCallById failed:" << r.error().message();
        return {};
    }
    return normalizeMapDeep(r.value());
}

QVariantList CallHistoryClient::getCallsByNumber(const QString &number) {
    QDBusReply<QVariantList> r = m_iface.call("GetCallsByNumber", number);
    if (!r.isValid()) {
        qWarning() << "[CallHistoryClient] GetCallsByNumber failed:" << r.error().message();
        return {};
    }
    return normalizeListDeep(r.value());
}

MediaLibraryClient::MediaLibraryClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/MediaLibrary",
              "org.marathonos.Shell.MediaLibrary1", QDBusConnection::sessionBus())
    , m_permIface("org.marathonos.Shell", "/org/marathonos/Shell/Permissions",
                  "org.marathonos.Shell.Permissions1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[MediaLibraryClient] DBus interface invalid:"
                   << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/MediaLibrary",
        "org.marathonos.Shell.MediaLibrary1", "AlbumsChanged", this, SLOT(refresh()));
    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/MediaLibrary",
        "org.marathonos.Shell.MediaLibrary1", "ScanComplete", this, SIGNAL(scanComplete(int, int)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell",
                                          "/org/marathonos/Shell/MediaLibrary",
                                          "org.marathonos.Shell.MediaLibrary1", "NewMediaAdded",
                                          this, SIGNAL(newMediaAdded(QString)));
    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/MediaLibrary",
        "org.marathonos.Shell.MediaLibrary1", "LibraryChanged", this, SLOT(onLibraryChanged()));
    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/MediaLibrary",
        "org.marathonos.Shell.MediaLibrary1", "ScanningChanged", this, SLOT(setScanning(bool)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell",
                                          "/org/marathonos/Shell/MediaLibrary",
                                          "org.marathonos.Shell.MediaLibrary1",
                                          "ScanProgressChanged", this, SLOT(setScanProgress(int)));

    refresh();
}

bool MediaLibraryClient::ensureStoragePermission() {
    QDBusReply<bool> r = m_permIface.call("HasPermission", m_appId, "storage");
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()))
            qWarning() << "[MediaLibraryClient] HasPermission(storage) failed:"
                       << r.error().message();
        return false;
    }
    if (r.value())
        return true;

    // Ask once: refresh() runs on every library signal, also in the background.
    if (m_storageRequested)
        return false;
    m_storageRequested = true;
    auto req           = m_permIface.call("RequestPermission", m_appId, "storage");
    if (req.type() == QDBusMessage::ErrorMessage && req.errorMessage().size())
        qWarning() << "[MediaLibraryClient] RequestPermission(storage) failed:"
                   << req.errorMessage();
    return false;
}

void MediaLibraryClient::setAlbums(const QVariantList &v) {
    m_albums = unwrapDbusVariantList(QVariant(v));
    emit albumsChanged();
}

void MediaLibraryClient::setScanning(bool scanning) {
    if (m_isScanning == scanning)
        return;
    m_isScanning = scanning;
    emit scanningChanged(scanning);
}

void MediaLibraryClient::setScanProgress(int progress) {
    if (m_scanProgress == progress)
        return;
    m_scanProgress = progress;
    emit scanProgressChanged(progress);
}

void MediaLibraryClient::onLibraryChanged() {

    QDBusReply<int> p = m_iface.call("PhotoCount");
    if (p.isValid())
        m_photoCount = p.value();

    QDBusReply<int> v = m_iface.call("VideoCount");
    if (v.isValid())
        m_videoCount = v.value();

    emit libraryChanged();
}

void MediaLibraryClient::refresh() {
    if (!ensureStoragePermission())
        return;

    QDBusReply<QVariantList> a = m_iface.call("Albums");
    if (!a.isValid()) {
        if (!isAccessDenied(a.error()))
            qWarning() << "[MediaLibraryClient] Albums failed:" << a.error().message();
        return;
    }
    setAlbums(a.value());

    QDBusReply<bool> s = m_iface.call("IsScanning");
    if (s.isValid())
        setScanning(s.value());

    onLibraryChanged();

    QDBusReply<int> sp = m_iface.call("ScanProgress");
    if (sp.isValid())
        setScanProgress(sp.value());
}

void MediaLibraryClient::scanLibrary() {
    if (!ensureStoragePermission())
        return;
    auto r = m_iface.call("ScanLibrary");
    if (r.type() == QDBusMessage::ErrorMessage && r.errorMessage().size())
        qWarning() << "[MediaLibraryClient] ScanLibrary failed:" << r.errorMessage();
}

void MediaLibraryClient::scanLibraryAsync() {
    if (!ensureStoragePermission())
        return;
    auto r = m_iface.call("ScanLibraryAsync");
    if (r.type() == QDBusMessage::ErrorMessage && r.errorMessage().size())
        qWarning() << "[MediaLibraryClient] ScanLibraryAsync failed:" << r.errorMessage();
}

QVariantList MediaLibraryClient::getPhotos(const QString &albumId) {
    if (!ensureStoragePermission())
        return {};
    QDBusReply<QVariantList> r = m_iface.call("GetPhotos", albumId);
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()))
            qWarning() << "[MediaLibraryClient] GetPhotos failed:" << r.error().message();
        return {};
    }
    return unwrapDbusVariantList(QVariant(r.value()));
}

QVariantList MediaLibraryClient::getAllPhotos() {
    if (!ensureStoragePermission())
        return {};
    QDBusReply<QVariantList> r = m_iface.call("GetAllPhotos");
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()))
            qWarning() << "[MediaLibraryClient] GetAllPhotos failed:" << r.error().message();
        return {};
    }
    return unwrapDbusVariantList(QVariant(r.value()));
}

QVariantList MediaLibraryClient::getVideos() {
    if (!ensureStoragePermission())
        return {};
    QDBusReply<QVariantList> r = m_iface.call("GetVideos");
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()))
            qWarning() << "[MediaLibraryClient] GetVideos failed:" << r.error().message();
        return {};
    }
    return unwrapDbusVariantList(QVariant(r.value()));
}

QString MediaLibraryClient::generateThumbnail(const QString &filePath) {
    if (!ensureStoragePermission())
        return {};
    QDBusReply<QString> r = m_iface.call("GenerateThumbnail", filePath);
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()))
            qWarning() << "[MediaLibraryClient] GenerateThumbnail failed:" << r.error().message();
        return {};
    }
    return r.value();
}

void MediaLibraryClient::deleteMedia(int mediaId) {
    if (!ensureStoragePermission())
        return;
    auto r = m_iface.call("DeleteMedia", mediaId);
    if (r.type() == QDBusMessage::ErrorMessage && r.errorMessage().size())
        qWarning() << "[MediaLibraryClient] DeleteMedia failed:" << r.errorMessage();
}

SecurityClient::SecurityClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Security",
              "org.marathonos.Shell.Security1", QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid())
        qWarning() << "[SecurityClient] DBus interface invalid:" << m_iface.lastError().message();

    m_startTimer.start();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Security",
                                          "org.marathonos.Shell.Security1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Security",
                                          "org.marathonos.Shell.Security1", "AuthenticationFailed",
                                          this, SIGNAL(authenticationFailed(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Security",
                                          "org.marathonos.Shell.Security1", "AuthenticationSuccess",
                                          this, SIGNAL(authenticationSuccess()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Security",
                                          "org.marathonos.Shell.Security1", "QuickPINChanged", this,
                                          SIGNAL(quickPINChanged()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Security",
                                          "org.marathonos.Shell.Security1", "EraseFailed", this,
                                          SIGNAL(eraseFailed(QString)));

    refresh();
}

bool SecurityClient::ensureSystemPermission() {
    if (m_appId.isEmpty())
        return false;
    QDBusReply<bool> r = m_permIface.call("HasPermission", m_appId, "system");
    if (!r.isValid())
        return false;
    if (r.value()) {
        m_permissionRequested = false;
        return true;
    }
    if (!m_permissionRequested) {
        m_permissionRequested = true;
        m_permIface.call("RequestPermission", m_appId, "system");
    }
    QTimer::singleShot(750, this, &SecurityClient::refresh);
    return false;
}

void SecurityClient::refresh() {
    if (m_refreshInFlight)
        return;
    m_refreshInFlight = true;
    m_iface.setTimeout(2000);

    if (!ensureSystemPermission()) {
        m_refreshInFlight = false;
        return;
    }

    auto  async = m_iface.asyncCall("GetState");
    auto *w     = new QDBusPendingCallWatcher(async, this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w]() {
        m_refreshInFlight                = false;
        QDBusPendingReply<QVariantMap> r = *w;
        w->deleteLater();
        if (!r.isValid()) {
            if (!m_loggedFirstFailure && debugEnabled()) {
                m_loggedFirstFailure = true;
                qWarning() << "[SecurityClient] Initial GetState failed:" << r.error().name()
                           << r.error().message();
            }
            if (m_refreshRetryCount < 40) {
                const int backoffMs = qMin(2000, 250 * (1 << qMin(m_refreshRetryCount / 8, 3)));
                ++m_refreshRetryCount;
                QTimer::singleShot(backoffMs, this, &SecurityClient::refresh);
            } else if (!isAccessDenied(r.error())) {
                qWarning() << "[SecurityClient] GetState failed:" << r.error().message();
            }
            return;
        }
        if (!m_loggedFirstSync) {
            m_loggedFirstSync = true;
            if (debugEnabled())
                qWarning() << "[SecurityClient] First sync after" << m_startTimer.elapsed() << "ms";
        }
        m_refreshRetryCount = 0;
        onStateChanged(normalizeMapDeep(r.value()));
    });
}

QVariant SecurityClient::v(const QString &k, const QVariant &fallback) const {
    return m_state.contains(k) ? m_state.value(k) : fallback;
}

void SecurityClient::onStateChanged(const QVariantMap &state) {
    m_state = normalizeMapDeep(state);
    emit stateChanged();
}

int SecurityClient::authMode() const {
    return v("authMode", 0).toInt();
}
bool SecurityClient::hasQuickPIN() const {
    return v("hasQuickPIN", false).toBool();
}
bool SecurityClient::fingerprintAvailable() const {
    return v("fingerprintAvailable", false).toBool();
}
bool SecurityClient::isLockedOut() const {
    return v("isLockedOut", false).toBool();
}
int SecurityClient::lockoutSecondsRemaining() const {
    return v("lockoutSecondsRemaining", 0).toInt();
}
int SecurityClient::failedAttempts() const {
    return v("failedAttempts", 0).toInt();
}
bool SecurityClient::canEraseAllContent() const {
    return v("canEraseAllContent", false).toBool();
}

QString SecurityClient::dataEncryption() const {
    return v("dataEncryption", QStringLiteral("none")).toString();
}

void SecurityClient::setQuickPIN(const QString &pin, const QString &systemPassword) {
    if (!ensureSystemPermission())
        return;
    m_iface.call("SetQuickPIN", pin, systemPassword);
}

void SecurityClient::removeQuickPIN(const QString &systemPassword) {
    if (!ensureSystemPermission())
        return;
    m_iface.call("RemoveQuickPIN", systemPassword);
}

void SecurityClient::authenticatePassword(const QString &password) {
    if (!ensureSystemPermission())
        return;
    m_iface.call("AuthenticatePassword", password);
}

void SecurityClient::authenticateQuickPIN(const QString &pin) {
    if (!ensureSystemPermission())
        return;
    m_iface.call("AuthenticateQuickPIN", pin);
}

void SecurityClient::authenticateBiometric(int type) {
    if (!ensureSystemPermission())
        return;
    m_iface.call("AuthenticateBiometric", type);
}

void SecurityClient::cancelAuthentication() {
    if (!ensureSystemPermission())
        return;
    m_iface.call("CancelAuthentication");
}

void SecurityClient::eraseAllContent(const QString &secret) {
    if (!ensureSystemPermission()) {
        emit eraseFailed(QStringLiteral("Settings isn't allowed to erase this device"));
        return;
    }
    // A wrong system password can keep the shell in PAM for longer than m_iface's timeout.
    QDBusMessage call = QDBusMessage::createMethodCall(m_iface.service(), m_iface.path(),
                                                       m_iface.interface(), "EraseAllContent");
    call << secret;
    auto *w = new QDBusPendingCallWatcher(m_iface.connection().asyncCall(call, 30000), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w] {
        const QDBusPendingReply<> r = *w;
        w->deleteLater();
        if (r.isError())
            emit eraseFailed(r.error().message());
    });
}

void SecurityClient::resetLockout() {
    if (!ensureSystemPermission())
        return;
    m_iface.call("ResetLockout");
}

bool SecurityClient::isBiometricEnrolled(int type) {
    if (!ensureSystemPermission())
        return false;
    QDBusReply<bool> r = m_iface.call("IsBiometricEnrolled", type);
    if (!r.isValid())
        return false;
    return r.value();
}

QString SecurityClient::currentUsername() {
    if (!ensureSystemPermission())
        return {};
    QDBusReply<QString> r = m_iface.call("CurrentUsername");
    if (!r.isValid())
        return {};
    return r.value();
}

BluetoothClient::BluetoothClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Bluetooth",
              "org.marathonos.Shell.Bluetooth1", QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid())
        qWarning() << "[BluetoothClient] DBus interface invalid:" << m_iface.lastError().message();

    m_startTimer.start();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Bluetooth",
                                          "org.marathonos.Shell.Bluetooth1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Bluetooth",
                                          "org.marathonos.Shell.Bluetooth1", "PairingFailed", this,
                                          SIGNAL(pairingFailed(QString, QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Bluetooth",
                                          "org.marathonos.Shell.Bluetooth1", "PairingSucceeded",
                                          this, SIGNAL(pairingSucceeded(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Bluetooth",
                                          "org.marathonos.Shell.Bluetooth1", "PinRequested", this,
                                          SIGNAL(pinRequested(QString, QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Bluetooth",
                                          "org.marathonos.Shell.Bluetooth1", "PasskeyRequested",
                                          this, SIGNAL(passkeyRequested(QString, QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Bluetooth",
                                          "org.marathonos.Shell.Bluetooth1", "PasskeyConfirmation",
                                          this,
                                          SIGNAL(passkeyConfirmation(QString, QString, uint)));

    refresh();
}

bool BluetoothClient::ensureSystemPermission() {
    if (m_appId.isEmpty())
        return false;
    QDBusReply<bool> r = m_permIface.call("HasPermission", m_appId, "system");
    if (!r.isValid())
        return false;
    if (r.value()) {
        m_permissionRequested = false;
        return true;
    }
    if (!m_permissionRequested) {
        m_permissionRequested = true;
        m_permIface.call("RequestPermission", m_appId, "system");
    }
    QTimer::singleShot(750, this, &BluetoothClient::refresh);
    return false;
}

void BluetoothClient::refresh() {
    if (m_refreshInFlight)
        return;
    m_refreshInFlight = true;
    m_iface.setTimeout(2000);

    if (!ensureSystemPermission()) {
        m_refreshInFlight = false;
        return;
    }

    auto  async = m_iface.asyncCall("GetState");
    auto *w     = new QDBusPendingCallWatcher(async, this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w]() {
        m_refreshInFlight                = false;
        QDBusPendingReply<QVariantMap> r = *w;
        w->deleteLater();

        if (!r.isValid()) {
            if (!m_loggedFirstFailure && debugEnabled()) {
                m_loggedFirstFailure = true;
                qWarning() << "[BluetoothClient] Initial GetState failed:" << r.error().name()
                           << r.error().message();
            }
            if (m_refreshRetryCount < 40) {
                const int backoffMs = qMin(2000, 250 * (1 << qMin(m_refreshRetryCount / 8, 3)));
                ++m_refreshRetryCount;
                QTimer::singleShot(backoffMs, this, &BluetoothClient::refresh);
            } else if (!isAccessDenied(r.error())) {
                qWarning() << "[BluetoothClient] GetState failed:" << r.error().message();
            }
            return;
        }

        m_refreshRetryCount = 0;
        if (!m_loggedFirstSync && debugEnabled()) {
            m_loggedFirstSync      = true;
            const int devicesCount = unwrapDbusVariantList(r.value().value("devices")).size();
            qWarning() << "[BluetoothClient] First sync after" << m_startTimer.elapsed()
                       << "ms enabled=" << r.value().value("enabled").toBool()
                       << "available=" << r.value().value("available").toBool()
                       << "devices=" << devicesCount;
        }
        onStateChanged(r.value());
    });
}

void BluetoothClient::onStateChanged(const QVariantMap &state) {
    QVariantMap normalized = state;

    normalized["devices"]       = unwrapDbusVariantList(normalized.value("devices"));
    normalized["pairedDevices"] = unwrapDbusVariantList(normalized.value("pairedDevices"));
    m_state                     = normalized;
    emit stateChanged();
}

bool BluetoothClient::available() const {
    return m_state.value("available").toBool();
}
bool BluetoothClient::enabled() const {
    return m_state.value("enabled").toBool();
}
void BluetoothClient::setEnabled(bool enabled) {
    auto r = m_iface.call("SetEnabled", enabled);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] SetEnabled failed:" << r.errorMessage();
}
bool BluetoothClient::scanning() const {
    return m_state.value("scanning").toBool();
}
QString BluetoothClient::adapterName() const {
    return m_state.value("adapterName").toString();
}
QVariantList BluetoothClient::devices() const {
    return m_state.value("devices").toList();
}
QVariantList BluetoothClient::pairedDevices() const {
    return m_state.value("pairedDevices").toList();
}

void BluetoothClient::startScan() {
    auto r = m_iface.call("StartScan");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] StartScan failed:" << r.errorMessage();
}
void BluetoothClient::stopScan() {
    auto r = m_iface.call("StopScan");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] StopScan failed:" << r.errorMessage();
}
void BluetoothClient::pairDevice(const QString &address, const QString &pin) {
    auto r = m_iface.call("PairDevice", address, pin);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] PairDevice failed:" << r.errorMessage();
}
void BluetoothClient::unpairDevice(const QString &address) {
    auto r = m_iface.call("UnpairDevice", address);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] UnpairDevice failed:" << r.errorMessage();
}
void BluetoothClient::connectDevice(const QString &address) {
    auto r = m_iface.call("ConnectDevice", address);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] ConnectDevice failed:" << r.errorMessage();
}
void BluetoothClient::disconnectDevice(const QString &address) {
    auto r = m_iface.call("DisconnectDevice", address);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] DisconnectDevice failed:" << r.errorMessage();
}
void BluetoothClient::confirmPairing(const QString &address, bool confirmed) {
    auto r = m_iface.call("ConfirmPairing", address, confirmed);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] ConfirmPairing failed:" << r.errorMessage();
}
void BluetoothClient::cancelPairing(const QString &address) {
    auto r = m_iface.call("CancelPairing", address);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[BluetoothClient] CancelPairing failed:" << r.errorMessage();
}


NavigationClient::NavigationClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Navigation",
              "org.marathonos.Shell.Navigation1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[NavigationClient] DBus interface invalid:" << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/Navigation",
        "org.marathonos.Shell.Navigation1", "AppLaunched", this, SIGNAL(appLaunched(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell",
                                          "/org/marathonos/Shell/Navigation",
                                          "org.marathonos.Shell.Navigation1", "NavigationFailed",
                                          this, SIGNAL(navigationFailed(QString, QString)));
    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/Navigation",
        "org.marathonos.Shell.Navigation1", "DeepLinkRequested", this,
        SLOT(onDeepLinkRequested(QString, QString, QString)));
}

void NavigationClient::onDeepLinkRequested(const QString &appId, const QString &route,
                                           const QString &paramsJson) {
    const QVariantMap params = QJsonDocument::fromJson(paramsJson.toUtf8()).object().toVariantMap();
    emit deepLinkRequested(appId, route, params);
}

SystemStatusStoreClient::SystemStatusStoreClient(marathon::platform::Power *powerClient,
                                                 marathon::platform::Network *networkClient, QObject *parent)
    : QObject(parent)
    , m_powerClient(powerClient)
    , m_networkClient(networkClient) {
    refreshPower();
    refreshNetwork();
    if (m_powerClient) {
        connect(m_powerClient, &marathon::platform::Power::stateChanged, this, [this]() { refreshPower(); });
    }
    if (m_networkClient) {
        connect(m_networkClient, &marathon::platform::Network::wifiConnectedChanged, this,
                [this]() { refreshNetwork(); });
        connect(m_networkClient, &marathon::platform::Network::wifiSsidChanged, this,
                [this]() { refreshNetwork(); });
    }
}

void SystemStatusStoreClient::refreshPower() {
    if (!m_powerClient) {
        setBatteryLevel(0);
        return;
    }
    setBatteryLevel(m_powerClient->getBatteryLevel());
}

void SystemStatusStoreClient::refreshNetwork() {
    if (!m_networkClient) {
        setWifiConnected(false);
        setWifiNetwork(QString());
        return;
    }
    setWifiConnected(m_networkClient->getWifiConnected());
    setWifiNetwork(m_networkClient->getWifiSsid());
}

void SystemStatusStoreClient::setBatteryLevel(int level) {
    if (m_batteryLevel == level) {
        return;
    }
    m_batteryLevel = level;
    emit batteryLevelChanged();
}

void SystemStatusStoreClient::setWifiConnected(bool connected) {
    if (m_wifiConnected == connected) {
        return;
    }
    m_wifiConnected = connected;
    emit wifiConnectedChanged();
}

void SystemStatusStoreClient::setWifiNetwork(const QString &network) {
    if (m_wifiNetwork == network) {
        return;
    }
    m_wifiNetwork = network;
    emit wifiNetworkChanged();
}

SystemControlStoreClient::SystemControlStoreClient(marathon::platform::Network *networkClient,
                                                   BluetoothClient *bluetoothClient,
                                                   marathon::platform::Display *displayClient,
                                                   marathon::platform::Settings *settingsClient,
                                                   Audio *audioClient, QObject *parent)
    : QObject(parent)
    , m_networkClient(networkClient)
    , m_bluetoothClient(bluetoothClient)
    , m_displayClient(displayClient)
    , m_settingsClient(settingsClient)
    , m_audioClient(audioClient) {
    refreshNetwork();
    refreshBluetooth();
    refreshDisplay();
    refreshSettings();
    refreshAudio();

    if (m_networkClient) {
        connect(m_networkClient, &marathon::platform::Network::wifiEnabledChanged, this,
                [this]() { refreshNetwork(); });
        connect(m_networkClient, &marathon::platform::Network::airplaneModeEnabledChanged, this,
                [this]() { refreshNetwork(); });
    }
    if (m_bluetoothClient) {
        connect(m_bluetoothClient, &BluetoothClient::stateChanged, this,
                [this]() { refreshBluetooth(); });
    }
    if (m_displayClient) {
        connect(m_displayClient, &marathon::platform::Display::stateChanged, this,
                [this]() { refreshDisplay(); });
    }
    if (m_settingsClient) {
        connect(m_settingsClient, &marathon::platform::Settings::dndEnabledChanged, this,
                [this]() { refreshSettings(); });
    }
    if (m_audioClient) {
        connect(m_audioClient, &Audio::stateChanged, this, [this]() { refreshAudio(); });
    }
}

void SystemControlStoreClient::toggleWifi() {
    if (m_networkClient) {
        m_networkClient->toggleWifi();
    }
}

void SystemControlStoreClient::toggleBluetooth() {
    if (m_bluetoothClient) {
        m_bluetoothClient->setEnabled(!m_bluetoothClient->enabled());
    }
}

void SystemControlStoreClient::toggleAirplaneMode() {
    if (m_networkClient) {
        m_networkClient->setAirplaneMode(!m_isAirplaneModeOn);
    }
}

void SystemControlStoreClient::toggleRotationLock() {
    if (m_displayClient) {
        m_displayClient->setRotationLocked(!m_isRotationLocked);
    }
}

void SystemControlStoreClient::toggleDndMode() {
    if (m_settingsClient) {
        m_settingsClient->setDndEnabled(!m_isDndMode);
    }
    if (m_audioClient) {
        m_audioClient->setDoNotDisturb(!m_isDndMode);
    }
}

void SystemControlStoreClient::setBrightness(int value) {
    const int clamped = std::max(0, std::min(100, value));
    if (m_displayClient) {
        m_displayClient->setBrightness(static_cast<double>(clamped) / 100.0);
    }
    setBrightnessValue(clamped);
}

void SystemControlStoreClient::setVolume(int value) {
    const int clamped = std::max(0, std::min(100, value));
    if (m_audioClient) {
        m_audioClient->setVolume(static_cast<double>(clamped) / 100.0);
    }
    setVolumeValue(clamped);
}

void SystemControlStoreClient::refreshNetwork() {
    if (!m_networkClient) {
        setIsWifiOn(true);
        setIsAirplaneModeOn(false);
        return;
    }
    setIsWifiOn(m_networkClient->getWifiEnabled());
    setIsAirplaneModeOn(m_networkClient->getAirplaneModeEnabled());
}

void SystemControlStoreClient::refreshBluetooth() {
    if (!m_bluetoothClient) {
        setIsBluetoothOn(false);
        return;
    }
    setIsBluetoothOn(m_bluetoothClient->enabled());
}

void SystemControlStoreClient::refreshDisplay() {
    if (!m_displayClient) {
        setIsRotationLocked(false);
        setBrightnessValue(50);
        return;
    }
    setIsRotationLocked(m_displayClient->getRotationLocked());
    setBrightnessValue(
        static_cast<int>(std::round(std::clamp(m_displayClient->getBrightness(), 0.0, 1.0) * 100.0)));
}

void SystemControlStoreClient::refreshSettings() {
    if (!m_settingsClient) {
        setIsDndMode(false);
        return;
    }
    setIsDndMode(m_settingsClient->getDndEnabled());
}

void SystemControlStoreClient::refreshAudio() {
    if (!m_audioClient) {
        setVolumeValue(50);
        return;
    }
    setVolumeValue(
        static_cast<int>(std::round(std::clamp(m_audioClient->getVolume(), 0.0, 1.0) * 100.0)));
}

void SystemControlStoreClient::setIsWifiOn(bool enabled) {
    if (m_isWifiOn == enabled) {
        return;
    }
    m_isWifiOn = enabled;
    emit isWifiOnChanged();
}

void SystemControlStoreClient::setIsBluetoothOn(bool enabled) {
    if (m_isBluetoothOn == enabled) {
        return;
    }
    m_isBluetoothOn = enabled;
    emit isBluetoothOnChanged();
}

void SystemControlStoreClient::setIsAirplaneModeOn(bool enabled) {
    if (m_isAirplaneModeOn == enabled) {
        return;
    }
    m_isAirplaneModeOn = enabled;
    emit isAirplaneModeOnChanged();
}

void SystemControlStoreClient::setIsRotationLocked(bool locked) {
    if (m_isRotationLocked == locked) {
        return;
    }
    m_isRotationLocked = locked;
    emit isRotationLockedChanged();
}

void SystemControlStoreClient::setIsDndMode(bool enabled) {
    if (m_isDndMode == enabled) {
        return;
    }
    m_isDndMode = enabled;
    emit isDndModeChanged();
}

void SystemControlStoreClient::setBrightnessValue(int value) {
    if (m_brightness == value) {
        return;
    }
    m_brightness = value;
    emit brightnessChanged();
}

void SystemControlStoreClient::setVolumeValue(int value) {
    if (m_volume == value) {
        return;
    }
    m_volume = value;
    emit volumeChanged();
}

bool NavigationClient::launchApp(const QString &appId) {
    if (appId.isEmpty()) {
        qWarning() << "[NavigationClient] launchApp: appId cannot be empty";
        return false;
    }

    QDBusReply<bool> r = m_iface.call("LaunchApp", appId);
    if (!r.isValid()) {
        qWarning() << "[NavigationClient] LaunchApp failed:" << r.error().message();
        return false;
    }
    return r.value();
}

bool NavigationClient::navigate(const QString &uri) {
    if (!uri.startsWith("marathon://")) {
        qWarning() << "[NavigationClient] navigate: URI must start with marathon://";
        return false;
    }

    QDBusReply<bool> r = m_iface.call("Navigate", uri);
    if (!r.isValid()) {
        qWarning() << "[NavigationClient] Navigate failed:" << r.error().message();
        return false;
    }
    return r.value();
}

bool NavigationClient::launchAppWithRoute(const QString &appId, const QString &route,
                                          const QString &paramsJson) {
    if (appId.isEmpty()) {
        qWarning() << "[NavigationClient] launchAppWithRoute: appId cannot be empty";
        return false;
    }

    QDBusReply<bool> r = m_iface.call("LaunchAppWithRoute", appId, route, paramsJson);
    if (!r.isValid()) {
        qWarning() << "[NavigationClient] LaunchAppWithRoute failed:" << r.error().message();
        return false;
    }
    return r.value();
}

HapticClient::HapticClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Haptic",
              "org.marathonos.Shell.Haptic1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[HapticClient] DBus interface invalid:" << m_iface.lastError().message();
    refresh();
}

void HapticClient::refresh() {
    QDBusReply<bool> r = m_iface.call("IsAvailable");
    if (r.isValid() && r.value() != m_available) {
        m_available = r.value();
        emit availableChanged();
    }
}

void HapticClient::light() {
    m_iface.call("Light");
}

void HapticClient::medium() {
    m_iface.call("Medium");
}

void HapticClient::heavy() {
    m_iface.call("Heavy");
}

void HapticClient::vibrate(int duration) {
    m_iface.call("Vibrate", duration);
}

void HapticClient::vibratePattern(const QVariantList &pattern, int repeat) {
    Q_UNUSED(repeat)
    m_iface.call("VibratePattern", pattern);
}

void HapticClient::stopVibration() {
    m_iface.call("Stop");
}

NotificationClient::NotificationClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface(notificationServiceName(), "/org/freedesktop/Notifications",
              "org.freedesktop.Notifications", QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid())
        qWarning() << "[NotificationClient] DBus interface invalid:"
                   << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect(m_iface.service(), "/org/freedesktop/Notifications",
                                          "org.freedesktop.Notifications", "NotificationClosed",
                                          this, SLOT(notificationClosed(int, int)));
    QDBusConnection::sessionBus().connect(m_iface.service(), "/org/freedesktop/Notifications",
                                          "org.freedesktop.Notifications", "ActionInvoked", this,
                                          SLOT(actionInvoked(int, QString)));
}

bool NotificationClient::ensurePermission() {
    if (m_appId.isEmpty())
        return false;
    QDBusReply<bool> r = m_permIface.call("HasPermission", m_appId, "notifications");
    if (!r.isValid())
        return false;
    if (r.value()) {
        m_permissionRequested = false;
        return true;
    }
    if (!m_permissionRequested) {
        m_permissionRequested = true;
        m_permIface.call("RequestPermission", m_appId, "notifications");
    }
    return false;
}

int NotificationClient::sendNotification(const QString &appId, const QString &title,
                                         const QString &body, const QVariantMap &options) {
    if (!ensurePermission())
        return -1;

    QStringList actions;
    if (options.contains("actions")) {
        QVariantList actionList = options.value("actions").toList();
        for (const QVariant &a : std::as_const(actionList)) {
            actions << a.toString() << a.toString();
        }
    }

    QVariantMap hints;
    if (options.contains("category"))
        hints["category"] = options.value("category");
    if (options.contains("priority")) {
        QString priority = options.value("priority").toString();
        hints["urgency"] = (priority == "high") ? 2 : ((priority == "low") ? 0 : 1);
    }
    hints["desktop-entry"] = appId;

    QString          icon    = options.value("icon").toString();
    int              timeout = options.value("persistent", false).toBool() ? 0 : 5000;

    QDBusReply<uint> r =
        m_iface.call("Notify", appId, 0u, icon, title, body, actions, hints, timeout);
    if (!r.isValid()) {
        qWarning() << "[NotificationClient] Notify failed:" << r.error().message();
        return -1;
    }
    return static_cast<int>(r.value());
}

void NotificationClient::dismissNotification(int id) {
    m_iface.call("CloseNotification", static_cast<uint>(id));
}

void NotificationClient::dismissAllNotifications() {

    qWarning() << "[NotificationClient] dismissAllNotifications not supported by freedesktop spec";
}



// === UpdateClient ===========================================================

UpdateClient::UpdateClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Updates",
              "org.marathonos.Shell.Updates1", QDBusConnection::sessionBus(), this) {
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Updates",
                                          "org.marathonos.Shell.Updates1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    refresh();
}

void UpdateClient::refresh() {
    QDBusReply<QVariantMap> r = m_iface.call("GetState");
    if (r.isValid()) {
        m_state = normalizeMapDeep(r.value());
        emit stateChanged();
    }
}

void UpdateClient::onStateChanged(const QVariantMap &state) {
    m_state = normalizeMapDeep(state);
    emit stateChanged();
}

void UpdateClient::checkNow() {
    m_iface.call("CheckNow");
}

void UpdateClient::install() {
    m_iface.call("Install");
}

void UpdateClient::cancel() {
    m_iface.call("Cancel");
}

void UpdateClient::reboot() {
    m_iface.call("Reboot");
}

void UpdateClient::scheduleRestart() {
    m_iface.call("ScheduleRestart");
}

void UpdateClient::setAutoUpdate(bool on) {
    m_iface.call("SetAutoUpdate", on);
}

// === DavClient ==============================================================

DavClient::DavClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Dav", "org.marathonos.Shell.Dav1",
              QDBusConnection::sessionBus(), this) {
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Dav",
                                          "org.marathonos.Shell.Dav1", "AccountsChanged", this,
                                          SLOT(onAccountsChanged()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Dav",
                                          "org.marathonos.Shell.Dav1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Dav",
                                          "org.marathonos.Shell.Dav1", "SyncFinished", this,
                                          SLOT(onSyncFinished(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Dav",
                                          "org.marathonos.Shell.Dav1", "AccountDiscovered", this,
                                          SIGNAL(accountDiscovered(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Dav",
                                          "org.marathonos.Shell.Dav1", "AccountDiscoveryFailed",
                                          this, SIGNAL(accountDiscoveryFailed(QString, QString)));
    refresh();
}

void DavClient::refresh() {
    refreshAccounts();
    refreshState();
}

void DavClient::refreshAccounts() {
    QDBusReply<QVariantList> r = m_iface.call("ListAccounts");
    if (r.isValid()) {
        m_accounts = normalizeListDeep(r.value());
        emit accountsChanged();
    }
}

void DavClient::refreshState() {
    QDBusReply<QVariantMap> r = m_iface.call("GetState");
    if (r.isValid()) {
        m_state = normalizeMapDeep(r.value());
        emit stateChanged();
    }
}

void DavClient::onAccountsChanged() {
    refreshAccounts();
}

void DavClient::onStateChanged(const QVariantMap &state) {
    m_state = normalizeMapDeep(state);
    emit stateChanged();
}

void DavClient::onSyncFinished(const QString &accountId) {
    emit syncFinished(accountId);
    refreshState();
}

QString DavClient::addAccount(const QString &displayName, const QString &baseUrl,
                              const QString &username, const QString &secret,
                              const QString &authKind) {
    QDBusReply<QString> r =
        m_iface.call("AddAccount", displayName, baseUrl, username, secret, authKind);
    return r.isValid() ? r.value() : QString();
}

bool DavClient::removeAccount(const QString &id) {
    QDBusReply<bool> r = m_iface.call("RemoveAccount", id);
    return r.isValid() && r.value();
}

void DavClient::enableAccount(const QString &id, bool enabled) {
    m_iface.call("EnableAccount", id, enabled);
}

void DavClient::syncNow() {
    m_iface.call("SyncNow");
}

// === AppInstallerClient =====================================================

AppInstallerClient::AppInstallerClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
              "org.marathonos.Shell.AppStore1", QDBusConnection::sessionBus(), this) {
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
                                          "org.marathonos.Shell.AppStore1", "UninstallComplete",
                                          this, SLOT(onUninstallComplete(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
                                          "org.marathonos.Shell.AppStore1", "UninstallFailed", this,
                                          SLOT(onUninstallFailed(QString, QString)));
}

bool AppInstallerClient::canUninstall(const QString &appId) {
    if (const auto known = m_removable.constFind(appId); known != m_removable.cend())
        return *known;
    QDBusReply<bool> r = m_iface.call("CanUninstall", appId);
    if (!r.isValid())
        return false;
    m_removable.insert(appId, r.value());
    return r.value();
}

// The shell's signal comes before its reply; a refused call has only the
// error reply.
void AppInstallerClient::uninstallApp(const QString &appId) {
    m_pending.insert(appId);
    auto *w = new QDBusPendingCallWatcher(m_iface.asyncCall("Uninstall", appId), this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w, appId]() {
        w->deleteLater();
        if (w->isError() && m_pending.remove(appId))
            emit uninstallFailed(appId, w->error().message());
    });
}

void AppInstallerClient::onUninstallComplete(const QString &appId) {
    m_removable.remove(appId);
    emit appRemoved(appId);
    if (m_pending.remove(appId))
        emit uninstallComplete(appId);
}

void AppInstallerClient::onUninstallFailed(const QString &appId, const QString &error) {
    if (m_pending.remove(appId))
        emit uninstallFailed(appId, error);
}

// === AppStoreClient =========================================================

AppStoreClient::AppStoreClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
              "org.marathonos.Shell.AppStore1", QDBusConnection::sessionBus(), this) {
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
                                          "org.marathonos.Shell.AppStore1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
                                          "org.marathonos.Shell.AppStore1", "CatalogRefreshed",
                                          this, SIGNAL(catalogRefreshed()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
                                          "org.marathonos.Shell.AppStore1", "DownloadProgress",
                                          this, SIGNAL(downloadProgress(QString, qint64, qint64)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
                                          "org.marathonos.Shell.AppStore1", "DownloadComplete",
                                          this, SIGNAL(downloadComplete(QString, QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/AppStore",
                                          "org.marathonos.Shell.AppStore1", "DownloadFailed", this,
                                          SIGNAL(downloadFailed(QString, QString)));
    refresh();
}

void AppStoreClient::refresh() {
    QDBusReply<QVariantMap> r = m_iface.call("GetState");
    if (r.isValid()) {
        m_state = normalizeMapDeep(r.value());
        emit stateChanged();
    }
}

void AppStoreClient::onStateChanged(const QVariantMap &state) {
    m_state = normalizeMapDeep(state);
    emit stateChanged();
}

void AppStoreClient::refreshCatalog() {
    m_iface.call("RefreshCatalog");
}

// Each catalog entry arrives as a QVariantList<QDBusArgument>; QML's
// JS engine can't see the inner QVariantMap keys until we qdbus_cast
// them back. We pull the raw reply via QDBusReply<QVariantList> (so
// QDBus does the type coercion) and then run the result through
// normalizeListDeep. Without this, every modelData.name read in QML
// came back undefined even though the row count was correct.
QVariantList AppStoreClient::searchApps(const QString &query) {
    QDBusReply<QVariantList> r = m_iface.call("SearchApps", query);
    if (!r.isValid())
        return {};
    return normalizeListDeep(r.value());
}

QVariantMap AppStoreClient::getApp(const QString &appId) {
    QDBusReply<QVariantMap> r = m_iface.call("GetApp", appId);
    if (!r.isValid())
        return {};
    return normalizeMapDeep(r.value());
}

QVariantList AppStoreClient::getFeaturedApps() {
    QDBusReply<QVariantList> r = m_iface.call("GetFeaturedApps");
    if (!r.isValid())
        return {};
    return normalizeListDeep(r.value());
}

QVariantList AppStoreClient::getAppsByCategory(const QString &category) {
    QDBusReply<QVariantList> r = m_iface.call("GetAppsByCategory", category);
    if (!r.isValid())
        return {};
    return normalizeListDeep(r.value());
}

QVariantList AppStoreClient::getAvailableUpdates() {
    QDBusReply<QVariantList> r = m_iface.call("GetAvailableUpdates");
    if (!r.isValid())
        return {};
    return normalizeListDeep(r.value());
}

void AppStoreClient::checkForUpdates() {
    m_iface.call("CheckForUpdates");
}

void AppStoreClient::downloadApp(const QString &appId) {
    m_iface.call("DownloadApp", appId);
}

void AppStoreClient::cancelDownload(const QString &appId) {
    m_iface.call("CancelDownload", appId);
}

AppLifecycleClient::AppLifecycleClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/AppLifecycle",
              "org.marathonos.Shell.AppLifecycle1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[AppLifecycleClient] DBus interface invalid:"
                   << m_iface.lastError().message();
}

quint32 AppLifecycleClient::beginBackgroundTask(const QString &category, const QString &reason) {
    QDBusReply<quint32> r = m_iface.call("BeginBackgroundTask", category, reason);
    if (!r.isValid()) {
        qWarning() << "[AppLifecycleClient] BeginBackgroundTask(" << category
                   << ") failed:" << r.error().message();
        return 0;
    }
    return r.value();
}

bool AppLifecycleClient::endBackgroundTask(quint32 handle) {
    QDBusReply<bool> r = m_iface.call("EndBackgroundTask", handle);
    if (!r.isValid()) {
        qWarning() << "[AppLifecycleClient] EndBackgroundTask(" << handle
                   << ") failed:" << r.error().message();
        return false;
    }
    return r.value();
}

QStringList AppLifecycleClient::currentCapabilities() {
    QDBusReply<QStringList> r = m_iface.call("GetMyCapabilities");
    if (!r.isValid())
        return {};
    return r.value();
}

void AppLifecycleClient::registerApp(const QString &appId, QObject *root) {
    Q_UNUSED(appId);
    Q_UNUSED(root);
    // No-op stub. See the declaration comment in shellipcclients.h.
}

void AppLifecycleClient::unregisterApp(const QString &appId) {
    Q_UNUSED(appId);
}
