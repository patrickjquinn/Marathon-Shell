#include "shellipcclients.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusVariant>
#include <QDebug>
#include <QTimer>
#include <algorithm>
#include <cmath>

static bool isAccessDenied(const QDBusError &e) {
    return e.type() == QDBusError::AccessDenied;
}

static bool debugEnabled() {
    const QByteArray v = qgetenv("MARATHON_DEBUG").trimmed().toLower();
    return v == "1" || v == "true";
}

static QVariant     normalizeDbusVariantDeep(QVariant v);

static QVariantList normalizeListDeep(const QVariantList &in) {
    QVariantList out;
    out.reserve(in.size());
    for (const QVariant &it : in)
        out.push_back(normalizeDbusVariantDeep(it));
    return out;
}

static QVariantMap normalizeMapDeep(const QVariantMap &in) {
    QVariantMap out;
    for (auto it = in.constBegin(); it != in.constEnd(); ++it)
        out.insert(it.key(), normalizeDbusVariantDeep(it.value()));
    return out;
}

static QVariant normalizeDbusVariantDeep(QVariant v) {

    if (v.canConvert<QDBusVariant>())
        v = v.value<QDBusVariant>().variant();

    if (v.userType() == qMetaTypeId<QDBusArgument>()) {

        const QVariantMap asMap = qdbus_cast<QVariantMap>(v);
        if (!asMap.isEmpty())
            return normalizeMapDeep(asMap);

        const QVariantList asList = qdbus_cast<QVariantList>(v);
        if (!asList.isEmpty())
            return normalizeListDeep(asList);

        return v;
    }

    if (v.metaType().id() == QMetaType::QVariantList)
        return normalizeListDeep(v.toList());
    if (v.metaType().id() == QMetaType::QVariantMap)
        return normalizeMapDeep(v.toMap());

    return v;
}

static QVariantList unwrapDbusVariantList(const QVariant &v) {

    QVariantList raw;
    if (v.canConvert<QDBusVariant>()) {
        raw = unwrapDbusVariantList(v.value<QDBusVariant>().variant());
        return raw;
    }
    if (v.userType() == qMetaTypeId<QDBusArgument>()) {
        raw = qdbus_cast<QVariantList>(v);
    } else {
        raw = v.toList();
    }
    return normalizeListDeep(raw);
}

static QDBusInterface makePermissionsIface(QObject *parent) {
    return QDBusInterface("org.marathonos.Shell", "/org/marathonos/Shell/Permissions",
                          "org.marathonos.Shell.Permissions1", QDBusConnection::sessionBus(),
                          parent);
}

static QString notificationServiceName() {
    auto *iface = QDBusConnection::sessionBus().interface();
    if (iface && iface->isServiceRegistered("org.marathon.Notifications"))
        return QStringLiteral("org.marathon.Notifications");
    return QStringLiteral("org.freedesktop.Notifications");
}

PermissionClient::PermissionClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Permissions",
              "org.marathonos.Shell.Permissions1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[PermissionClient] DBus interface invalid:" << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell",
                                          "/org/marathonos/Shell/Permissions",
                                          "org.marathonos.Shell.Permissions1", "PermissionGranted",
                                          this, SIGNAL(permissionGranted(QString, QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell",
                                          "/org/marathonos/Shell/Permissions",
                                          "org.marathonos.Shell.Permissions1", "PermissionDenied",
                                          this, SIGNAL(permissionDenied(QString, QString)));
    QDBusConnection::sessionBus().connect(
        "org.marathonos.Shell", "/org/marathonos/Shell/Permissions",
        "org.marathonos.Shell.Permissions1", "PermissionRequested", this,
        SIGNAL(permissionRequested(QString, QString)));
}

bool PermissionClient::hasPermission(const QString &appId, const QString &permission) {
    QDBusReply<bool> r = m_iface.call("HasPermission", appId, permission);
    if (!r.isValid()) {
        qWarning() << "[PermissionClient] HasPermission failed:" << r.error().message();
        return false;
    }
    return r.value();
}

void PermissionClient::requestPermission(const QString &appId, const QString &permission) {
    auto r = m_iface.call("RequestPermission", appId, permission);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[PermissionClient] RequestPermission failed:" << r.errorMessage();
}

void PermissionClient::setPermission(const QString &appId, const QString &permission, bool granted,
                                     bool remember) {
    auto r = m_iface.call("SetPermission", appId, permission, granted, remember);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[PermissionClient] SetPermission failed:" << r.errorMessage();
}

ContactsClient::ContactsClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Contacts",
              "org.marathonos.Shell.Contacts1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid()) {
        qWarning() << "[ContactsClient] DBus interface invalid:" << m_iface.lastError().message();
        return;
    }
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Contacts",
                                          "org.marathonos.Shell.Contacts1", "ContactsChanged", this,
                                          SLOT(refresh()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Contacts",
                                          "org.marathonos.Shell.Contacts1", "ContactAdded", this,
                                          SIGNAL(contactAdded(int)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Contacts",
                                          "org.marathonos.Shell.Contacts1", "ContactUpdated", this,
                                          SIGNAL(contactUpdated(int)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Contacts",
                                          "org.marathonos.Shell.Contacts1", "ContactDeleted", this,
                                          SIGNAL(contactDeleted(int)));
    refresh();
}

void ContactsClient::setContacts(const QVariantList &v) {
    m_contacts = v;
    emit contactsChanged();
}

void ContactsClient::refresh() {
    QDBusReply<QVariantList> r = m_iface.call("GetContacts");
    if (!r.isValid()) {
        if (r.error().type() != QDBusError::AccessDenied)
            qWarning() << "[ContactsClient] GetContacts failed:" << r.error().message();
        return;
    }
    setContacts(r.value());
}

void ContactsClient::addContact(const QString &name, const QString &phone, const QString &email) {
    auto r = m_iface.call("AddContact", name, phone, email);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[ContactsClient] AddContact failed:" << r.errorMessage();
}

void ContactsClient::updateContact(int id, const QVariantMap &data) {
    auto r = m_iface.call("UpdateContact", id, data);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[ContactsClient] UpdateContact failed:" << r.errorMessage();
}

void ContactsClient::deleteContact(int id) {
    auto r = m_iface.call("DeleteContact", id);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[ContactsClient] DeleteContact failed:" << r.errorMessage();
}

QVariantList ContactsClient::searchContacts(const QString &query) {
    QDBusReply<QVariantList> r = m_iface.call("SearchContacts", query);
    if (!r.isValid()) {
        qWarning() << "[ContactsClient] SearchContacts failed:" << r.error().message();
        return {};
    }
    return r.value();
}

QVariantMap ContactsClient::getContact(int id) {
    QDBusReply<QVariantMap> r = m_iface.call("GetContact", id);
    if (!r.isValid()) {
        qWarning() << "[ContactsClient] GetContact failed:" << r.error().message();
        return {};
    }
    return r.value();
}

QVariantMap ContactsClient::getContactByNumber(const QString &phoneNumber) {
    QDBusReply<QVariantMap> r = m_iface.call("GetContactByNumber", phoneNumber);
    if (!r.isValid()) {
        qWarning() << "[ContactsClient] GetContactByNumber failed:" << r.error().message();
        return {};
    }
    return r.value();
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
    m_history = v;
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
    return r.value();
}

QVariantList CallHistoryClient::getCallsByNumber(const QString &number) {
    QDBusReply<QVariantList> r = m_iface.call("GetCallsByNumber", number);
    if (!r.isValid()) {
        qWarning() << "[CallHistoryClient] GetCallsByNumber failed:" << r.error().message();
        return {};
    }
    return r.value();
}

TelephonyClient::TelephonyClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Telephony",
              "org.marathonos.Shell.Telephony1", QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid()) {
        qWarning() << "[TelephonyClient] DBus interface invalid:" << m_iface.lastError().message();
        return;
    }

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Telephony",
                                          "org.marathonos.Shell.Telephony1", "CallStateChanged",
                                          this, SLOT(setCallState(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Telephony",
                                          "org.marathonos.Shell.Telephony1", "IncomingCall", this,
                                          SIGNAL(incomingCall(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Telephony",
                                          "org.marathonos.Shell.Telephony1", "CallFailed", this,
                                          SIGNAL(callFailed(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Telephony",
                                          "org.marathonos.Shell.Telephony1", "ModemChanged", this,
                                          SLOT(setHasModem(bool)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Telephony",
                                          "org.marathonos.Shell.Telephony1", "ActiveNumberChanged",
                                          this, SLOT(setActiveNumber(QString)));
    refresh();
}

bool TelephonyClient::ensurePermission() {
    if (m_appId.isEmpty())
        return false;
    QDBusReply<bool> rTelephony = m_permIface.call("HasPermission", m_appId, "telephony");
    if (rTelephony.isValid() && rTelephony.value()) {
        m_permissionRequested = false;
        return true;
    }
    QDBusReply<bool> rPhone = m_permIface.call("HasPermission", m_appId, "phone");
    if (rPhone.isValid() && rPhone.value()) {
        m_permissionRequested = false;
        return true;
    }
    if (!rTelephony.isValid() && !rPhone.isValid())
        return false;
    if (!m_permissionRequested) {
        m_permissionRequested = true;
        m_permIface.call("RequestPermission", m_appId, "telephony");
    }
    QTimer::singleShot(750, this, &TelephonyClient::refresh);
    return false;
}

void TelephonyClient::setCallState(const QString &s) {
    if (m_callState == s)
        return;
    m_callState = s;
    emit callStateChanged(s);
}
void TelephonyClient::setHasModem(bool b) {
    if (m_hasModem == b)
        return;
    m_hasModem = b;
    emit modemChanged(b);
}
void TelephonyClient::setActiveNumber(const QString &n) {
    if (m_activeNumber == n)
        return;
    m_activeNumber = n;
    emit activeNumberChanged(n);
}

void TelephonyClient::refresh() {
    if (!ensurePermission())
        return;
    QDBusReply<QString> cs = m_iface.call("CallState");
    if (cs.isValid())
        setCallState(cs.value());
    QDBusReply<bool> hm = m_iface.call("HasModem");
    if (hm.isValid())
        setHasModem(hm.value());
    QDBusReply<QString> an = m_iface.call("ActiveNumber");
    if (an.isValid())
        setActiveNumber(an.value());
}

void TelephonyClient::dial(const QString &number) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("Dial", number);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] Dial failed:" << r.errorMessage();
}
void TelephonyClient::answer() {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("Answer");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] Answer failed:" << r.errorMessage();
}
void TelephonyClient::hangup() {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("Hangup");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] Hangup failed:" << r.errorMessage();
}
void TelephonyClient::sendDTMF(const QString &digit) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("SendDTMF", digit);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] SendDTMF failed:" << r.errorMessage();
}

void TelephonyClient::simulateIncomingCall(const QString &number) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("SimulateIncomingCall", number);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] SimulateIncomingCall failed:" << r.errorMessage();
}

void TelephonyClient::simulateCallStateChange(const QString &state) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("SimulateCallStateChange", state);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] SimulateCallStateChange failed:" << r.errorMessage();
}

void TelephonyClient::setSpeakerphone(bool on) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("SetSpeakerphone", on);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] SetSpeakerphone failed:" << r.errorMessage();
}

void TelephonyClient::setCallMuted(bool muted) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("SetCallMuted", muted);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[TelephonyClient] SetCallMuted failed:" << r.errorMessage();
}

bool TelephonyClient::isSpeakerphoneOn() {
    if (!ensurePermission())
        return false;
    QDBusReply<bool> r = m_iface.call("IsSpeakerphoneOn");
    return r.isValid() ? r.value() : false;
}

bool TelephonyClient::isCallMuted() {
    if (!ensurePermission())
        return false;
    QDBusReply<bool> r = m_iface.call("IsCallMuted");
    return r.isValid() ? r.value() : false;
}

SmsClient::SmsClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Sms", "org.marathonos.Shell.Sms1",
              QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid()) {
        qWarning() << "[SmsClient] DBus interface invalid:" << m_iface.lastError().message();
        return;
    }
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Sms",
                                          "org.marathonos.Shell.Sms1", "MessageReceived", this,
                                          SIGNAL(messageReceived(QString, QString, qint64)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Sms",
                                          "org.marathonos.Shell.Sms1", "MessageSent", this,
                                          SIGNAL(messageSent(QString, qint64)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Sms",
                                          "org.marathonos.Shell.Sms1", "SendFailed", this,
                                          SIGNAL(sendFailed(QString, QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Sms",
                                          "org.marathonos.Shell.Sms1", "ConversationsChanged", this,
                                          SLOT(refresh()));
    refresh();
}

bool SmsClient::ensurePermission() {
    if (m_appId.isEmpty())
        return false;
    QDBusReply<bool> rSms = m_permIface.call("HasPermission", m_appId, "sms");
    if (rSms.isValid() && rSms.value()) {
        m_permissionRequested = false;
        return true;
    }
    QDBusReply<bool> rPhone = m_permIface.call("HasPermission", m_appId, "phone");
    if (rPhone.isValid() && rPhone.value()) {
        m_permissionRequested = false;
        return true;
    }
    if (!rSms.isValid() && !rPhone.isValid())
        return false;
    if (!m_permissionRequested) {
        m_permissionRequested = true;
        m_permIface.call("RequestPermission", m_appId, "sms");
    }
    QTimer::singleShot(750, this, &SmsClient::refresh);
    return false;
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

    auto req = m_permIface.call("RequestPermission", m_appId, "storage");
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

SettingsClient::SettingsClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Settings",
              "org.marathonos.Shell.Settings1", QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid())
        qWarning() << "[SettingsClient] DBus interface invalid:" << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Settings",
                                          "org.marathonos.Shell.Settings1", "PropertyChanged", this,
                                          SLOT(onPropertyChanged(QString, QDBusVariant)));
    refresh();
}

bool SettingsClient::ensureSystemPermission() {
    if (m_appId.isEmpty())
        return false;

    QDBusReply<bool> r = m_permIface.call("HasPermission", m_appId, "system");
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()) && debugEnabled())
            qWarning() << "[SettingsClient] HasPermission(system) failed:" << r.error().message();
        return false;
    }

    if (r.value()) {
        m_permissionRequested = false;
        return true;
    }

    if (!m_permissionRequested) {
        m_permissionRequested = true;
        auto req              = m_permIface.call("RequestPermission", m_appId, "system");
        if (req.type() == QDBusMessage::ErrorMessage && debugEnabled())
            qWarning() << "[SettingsClient] RequestPermission(system) failed:"
                       << req.errorMessage();
    }

    QTimer::singleShot(750, this, &SettingsClient::refresh);
    return false;
}

bool SettingsClient::ensureStoragePermission() {
    if (m_appId.isEmpty())
        return false;

    QDBusReply<bool> r = m_permIface.call("HasPermission", m_appId, "storage");
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()) && debugEnabled())
            qWarning() << "[SettingsClient] HasPermission(storage) failed:" << r.error().message();
        return false;
    }

    if (r.value()) {
        m_storageRequested = false;
        return true;
    }

    if (!m_storageRequested) {
        m_storageRequested = true;
        auto req           = m_permIface.call("RequestPermission", m_appId, "storage");
        if (req.type() == QDBusMessage::ErrorMessage && debugEnabled())
            qWarning() << "[SettingsClient] RequestPermission(storage) failed:"
                       << req.errorMessage();
    }

    QTimer::singleShot(750, this, &SettingsClient::refresh);
    return false;
}

bool SettingsClient::isAppScopedKey(const QString &key) const {
    if (m_appId.isEmpty())
        return false;
    return key.startsWith(m_appId + "/");
}

bool SettingsClient::ensurePermissionForKey(const QString &key) {
    return isAppScopedKey(key) ? ensureStoragePermission() : ensureSystemPermission();
}

void SettingsClient::refresh() {
    if (m_refreshInFlight)
        return;
    m_refreshInFlight = true;

    // GetState is a read — it returns userScaleFactor, wallpaperPath,
    // timeFormat, theme tokens etc. that every app needs to size its UI.
    // It does NOT require a permission, so don't pre-prompt the user.
    // Writes (setProp) still gate on ensureSystemPermission below.

    m_iface.setTimeout(2000);

    auto  async = m_iface.asyncCall("GetState");
    auto *w     = new QDBusPendingCallWatcher(async, this);
    connect(w, &QDBusPendingCallWatcher::finished, this, [this, w]() {
        m_refreshInFlight                = false;
        QDBusPendingReply<QVariantMap> r = *w;
        w->deleteLater();

        if (!r.isValid()) {
            if (!isAccessDenied(r.error()) && debugEnabled())
                qWarning() << "[SettingsClient] GetState failed:" << r.error().name()
                           << r.error().message();

            QTimer::singleShot(250, this, &SettingsClient::refresh);
            return;
        }

        m_state = r.value();

        emit userScaleFactorChanged();
        emit wallpaperPathChanged();
        emit deviceNameChanged();
        emit autoLockChanged();
        emit autoLockTimeoutChanged();
        emit showNotificationPreviewsChanged();
        emit timeFormatChanged();
        emit dateFormatChanged();
        emit ringtoneChanged();
        emit notificationSoundChanged();
        emit alarmSoundChanged();
        emit mediaVolumeChanged();
        emit ringtoneVolumeChanged();
        emit alarmVolumeChanged();
        emit notificationVolumeChanged();
        emit systemVolumeChanged();
        emit dndEnabledChanged();
        emit vibrationEnabledChanged();
        emit audioProfileChanged();
        emit screenTimeoutChanged();
        emit autoBrightnessChanged();
        emit statusBarClockPositionChanged();
        emit showNotificationsOnLockScreenChanged();
        emit filterMobileFriendlyAppsChanged();
        emit hiddenAppsChanged();
        emit appSortOrderChanged();
        emit appGridColumnsChanged();
        emit searchNativeAppsChanged();
        emit showNotificationBadgesChanged();
        emit showFrequentAppsChanged();
        emit defaultAppsChanged();
        emit firstRunCompleteChanged();
        emit enabledQuickSettingsTilesChanged();
        emit quickSettingsTileOrderChanged();
        emit keyboardAutoCorrectionChanged();
        emit keyboardPredictiveTextChanged();
        emit keyboardWordFlingChanged();
        emit keyboardPredictiveSpacingChanged();
        emit keyboardHapticStrengthChanged();
    });
}

QVariant SettingsClient::prop(const QString &name, const QVariant &fallback) const {
    return m_state.contains(name) ? m_state.value(name) : fallback;
}

void SettingsClient::setProp(const QString &name, const QVariant &value) {
    if (!ensureSystemPermission())
        return;
    auto msg = m_iface.call("SetProperty", name, QVariant::fromValue(QDBusVariant(value)));
    if (msg.type() == QDBusMessage::ErrorMessage) {
        if (!msg.errorMessage().isEmpty())
            qWarning() << "[SettingsClient] SetProperty failed:" << msg.errorMessage();
        return;
    }

    m_state.insert(name, value);
    onPropertyChanged(name, QDBusVariant(value));
}

void SettingsClient::onPropertyChanged(const QString &name, const QDBusVariant &value) {
    m_state.insert(name, value.variant());

    using Notify                                           = void (SettingsClient::*)();
    static const QHash<QString, Notify> kSignalForProperty = {
        {"userScaleFactor", &SettingsClient::userScaleFactorChanged},
        {"wallpaperPath", &SettingsClient::wallpaperPathChanged},
        {"deviceName", &SettingsClient::deviceNameChanged},
        {"autoLock", &SettingsClient::autoLockChanged},
        {"autoLockTimeout", &SettingsClient::autoLockTimeoutChanged},
        {"showNotificationPreviews", &SettingsClient::showNotificationPreviewsChanged},
        {"timeFormat", &SettingsClient::timeFormatChanged},
        {"dateFormat", &SettingsClient::dateFormatChanged},
        {"ringtone", &SettingsClient::ringtoneChanged},
        {"notificationSound", &SettingsClient::notificationSoundChanged},
        {"alarmSound", &SettingsClient::alarmSoundChanged},
        {"mediaVolume", &SettingsClient::mediaVolumeChanged},
        {"ringtoneVolume", &SettingsClient::ringtoneVolumeChanged},
        {"alarmVolume", &SettingsClient::alarmVolumeChanged},
        {"notificationVolume", &SettingsClient::notificationVolumeChanged},
        {"systemVolume", &SettingsClient::systemVolumeChanged},
        {"dndEnabled", &SettingsClient::dndEnabledChanged},
        {"vibrationEnabled", &SettingsClient::vibrationEnabledChanged},
        {"audioProfile", &SettingsClient::audioProfileChanged},
        {"screenTimeout", &SettingsClient::screenTimeoutChanged},
        {"autoBrightness", &SettingsClient::autoBrightnessChanged},
        {"statusBarClockPosition", &SettingsClient::statusBarClockPositionChanged},
        {"showNotificationsOnLockScreen", &SettingsClient::showNotificationsOnLockScreenChanged},
        {"filterMobileFriendlyApps", &SettingsClient::filterMobileFriendlyAppsChanged},
        {"hiddenApps", &SettingsClient::hiddenAppsChanged},
        {"appSortOrder", &SettingsClient::appSortOrderChanged},
        {"appGridColumns", &SettingsClient::appGridColumnsChanged},
        {"searchNativeApps", &SettingsClient::searchNativeAppsChanged},
        {"showNotificationBadges", &SettingsClient::showNotificationBadgesChanged},
        {"appNotificationSettings", &SettingsClient::appNotificationSettingsChanged},
        {"showFrequentApps", &SettingsClient::showFrequentAppsChanged},
        {"defaultApps", &SettingsClient::defaultAppsChanged},
        {"firstRunComplete", &SettingsClient::firstRunCompleteChanged},
        {"enabledQuickSettingsTiles", &SettingsClient::enabledQuickSettingsTilesChanged},
        {"quickSettingsTileOrder", &SettingsClient::quickSettingsTileOrderChanged},
        {"keyboardAutoCorrection", &SettingsClient::keyboardAutoCorrectionChanged},
        {"keyboardPredictiveText", &SettingsClient::keyboardPredictiveTextChanged},
        {"keyboardWordFling", &SettingsClient::keyboardWordFlingChanged},
        {"keyboardPredictiveSpacing", &SettingsClient::keyboardPredictiveSpacingChanged},
        {"keyboardHapticStrength", &SettingsClient::keyboardHapticStrengthChanged},
    };
    if (auto it = kSignalForProperty.constFind(name); it != kSignalForProperty.constEnd())
        (this->**it)();
}

qreal SettingsClient::userScaleFactor() const {
    return prop("userScaleFactor", 1.0).toReal();
}
QString SettingsClient::wallpaperPath() const {
    return prop("wallpaperPath", "").toString();
}
QString SettingsClient::deviceName() const {
    return prop("deviceName", "").toString();
}
bool SettingsClient::autoLock() const {
    return prop("autoLock", true).toBool();
}
int SettingsClient::autoLockTimeout() const {
    return prop("autoLockTimeout", 0).toInt();
}
bool SettingsClient::showNotificationPreviews() const {
    return prop("showNotificationPreviews", true).toBool();
}
QString SettingsClient::timeFormat() const {
    return prop("timeFormat", "24h").toString();
}
QString SettingsClient::dateFormat() const {
    return prop("dateFormat", "US").toString();
}

QString SettingsClient::ringtone() const {
    return prop("ringtone", "").toString();
}
QString SettingsClient::notificationSound() const {
    return prop("notificationSound", "").toString();
}
QString SettingsClient::alarmSound() const {
    return prop("alarmSound", "").toString();
}
qreal SettingsClient::mediaVolume() const {
    return prop("mediaVolume", 0.0).toReal();
}
qreal SettingsClient::ringtoneVolume() const {
    return prop("ringtoneVolume", 0.0).toReal();
}
qreal SettingsClient::alarmVolume() const {
    return prop("alarmVolume", 0.0).toReal();
}
qreal SettingsClient::notificationVolume() const {
    return prop("notificationVolume", 0.0).toReal();
}
qreal SettingsClient::systemVolume() const {
    return prop("systemVolume", 0.0).toReal();
}
bool SettingsClient::dndEnabled() const {
    return prop("dndEnabled", false).toBool();
}
bool SettingsClient::vibrationEnabled() const {
    return prop("vibrationEnabled", true).toBool();
}
QString SettingsClient::audioProfile() const {
    return prop("audioProfile", "normal").toString();
}

int SettingsClient::screenTimeout() const {
    return prop("screenTimeout", 0).toInt();
}
bool SettingsClient::autoBrightness() const {
    return prop("autoBrightness", false).toBool();
}
QString SettingsClient::statusBarClockPosition() const {
    return prop("statusBarClockPosition", "center").toString();
}

bool SettingsClient::showNotificationsOnLockScreen() const {
    return prop("showNotificationsOnLockScreen", true).toBool();
}

bool SettingsClient::filterMobileFriendlyApps() const {
    return prop("filterMobileFriendlyApps", true).toBool();
}
QStringList SettingsClient::hiddenApps() const {
    return prop("hiddenApps", QStringList{}).toStringList();
}
QString SettingsClient::appSortOrder() const {
    return prop("appSortOrder", "alphabetical").toString();
}
int SettingsClient::appGridColumns() const {
    return prop("appGridColumns", 0).toInt();
}
bool SettingsClient::searchNativeApps() const {
    return prop("searchNativeApps", true).toBool();
}
bool SettingsClient::showNotificationBadges() const {
    return prop("showNotificationBadges", true).toBool();
}
QVariantMap SettingsClient::appNotificationSettings() const {
    return prop("appNotificationSettings", QVariantMap{}).toMap();
}
bool SettingsClient::showFrequentApps() const {
    return prop("showFrequentApps", false).toBool();
}
QVariantMap SettingsClient::defaultApps() const {
    return prop("defaultApps", QVariantMap{}).toMap();
}

bool SettingsClient::firstRunComplete() const {
    return prop("firstRunComplete", false).toBool();
}

QStringList SettingsClient::enabledQuickSettingsTiles() const {
    return prop("enabledQuickSettingsTiles", QStringList{}).toStringList();
}
QStringList SettingsClient::quickSettingsTileOrder() const {
    return prop("quickSettingsTileOrder", QStringList{}).toStringList();
}

bool SettingsClient::keyboardAutoCorrection() const {
    return prop("keyboardAutoCorrection", true).toBool();
}
bool SettingsClient::keyboardPredictiveText() const {
    return prop("keyboardPredictiveText", true).toBool();
}
bool SettingsClient::keyboardWordFling() const {
    return prop("keyboardWordFling", true).toBool();
}
bool SettingsClient::keyboardPredictiveSpacing() const {
    return prop("keyboardPredictiveSpacing", false).toBool();
}
QString SettingsClient::keyboardHapticStrength() const {
    return prop("keyboardHapticStrength", "medium").toString();
}

void SettingsClient::setUserScaleFactor(qreal v) {
    setProp("userScaleFactor", v);
}
void SettingsClient::setWallpaperPath(const QString &v) {
    setProp("wallpaperPath", v);
}
void SettingsClient::setDeviceName(const QString &v) {
    setProp("deviceName", v);
}
void SettingsClient::setAutoLock(bool v) {
    setProp("autoLock", v);
}
void SettingsClient::setAutoLockTimeout(int v) {
    setProp("autoLockTimeout", v);
}
void SettingsClient::setShowNotificationPreviews(bool v) {
    setProp("showNotificationPreviews", v);
}
void SettingsClient::setTimeFormat(const QString &v) {
    setProp("timeFormat", v);
}
void SettingsClient::setDateFormat(const QString &v) {
    setProp("dateFormat", v);
}

void SettingsClient::setRingtone(const QString &v) {
    setProp("ringtone", v);
}
void SettingsClient::setNotificationSound(const QString &v) {
    setProp("notificationSound", v);
}
void SettingsClient::setAlarmSound(const QString &v) {
    setProp("alarmSound", v);
}
void SettingsClient::setMediaVolume(qreal v) {
    setProp("mediaVolume", v);
}
void SettingsClient::setRingtoneVolume(qreal v) {
    setProp("ringtoneVolume", v);
}
void SettingsClient::setAlarmVolume(qreal v) {
    setProp("alarmVolume", v);
}
void SettingsClient::setNotificationVolume(qreal v) {
    setProp("notificationVolume", v);
}
void SettingsClient::setSystemVolume(qreal v) {
    setProp("systemVolume", v);
}
void SettingsClient::setDndEnabled(bool v) {
    setProp("dndEnabled", v);
}
void SettingsClient::setVibrationEnabled(bool v) {
    setProp("vibrationEnabled", v);
}
void SettingsClient::setAudioProfile(const QString &v) {
    setProp("audioProfile", v);
}

void SettingsClient::setScreenTimeout(int v) {
    setProp("screenTimeout", v);
}
void SettingsClient::setAutoBrightness(bool v) {
    setProp("autoBrightness", v);
}
void SettingsClient::setStatusBarClockPosition(const QString &v) {
    setProp("statusBarClockPosition", v);
}

void SettingsClient::setShowNotificationsOnLockScreen(bool v) {
    setProp("showNotificationsOnLockScreen", v);
}

void SettingsClient::setFilterMobileFriendlyApps(bool v) {
    setProp("filterMobileFriendlyApps", v);
}
void SettingsClient::setHiddenApps(const QStringList &v) {
    setProp("hiddenApps", v);
}
void SettingsClient::setAppSortOrder(const QString &v) {
    setProp("appSortOrder", v);
}
void SettingsClient::setAppGridColumns(int v) {
    setProp("appGridColumns", v);
}
void SettingsClient::setSearchNativeApps(bool v) {
    setProp("searchNativeApps", v);
}
void SettingsClient::setShowNotificationBadges(bool v) {
    setProp("showNotificationBadges", v);
}
void SettingsClient::setAppNotificationSettings(const QVariantMap &settings) {
    setProp("appNotificationSettings", settings);
}
void SettingsClient::setShowFrequentApps(bool v) {
    setProp("showFrequentApps", v);
}
void SettingsClient::setDefaultApps(const QVariantMap &v) {
    setProp("defaultApps", v);
}

void SettingsClient::setFirstRunComplete(bool v) {
    setProp("firstRunComplete", v);
}

void SettingsClient::setEnabledQuickSettingsTiles(const QStringList &v) {
    setProp("enabledQuickSettingsTiles", v);
}
void SettingsClient::setQuickSettingsTileOrder(const QStringList &v) {
    setProp("quickSettingsTileOrder", v);
}

void SettingsClient::setKeyboardAutoCorrection(bool v) {
    setProp("keyboardAutoCorrection", v);
}
void SettingsClient::setKeyboardPredictiveText(bool v) {
    setProp("keyboardPredictiveText", v);
}
void SettingsClient::setKeyboardWordFling(bool v) {
    setProp("keyboardWordFling", v);
}
void SettingsClient::setKeyboardPredictiveSpacing(bool v) {
    setProp("keyboardPredictiveSpacing", v);
}
void SettingsClient::setKeyboardHapticStrength(const QString &v) {
    setProp("keyboardHapticStrength", v);
}

QStringList SettingsClient::availableRingtones() {
    if (!ensureSystemPermission())
        return {};
    QDBusReply<QStringList> r = m_iface.call("AvailableRingtones");
    return r.isValid() ? r.value() : QStringList{};
}
QStringList SettingsClient::availableNotificationSounds() {
    if (!ensureSystemPermission())
        return {};
    QDBusReply<QStringList> r = m_iface.call("AvailableNotificationSounds");
    return r.isValid() ? r.value() : QStringList{};
}
QStringList SettingsClient::availableAlarmSounds() {
    if (!ensureSystemPermission())
        return {};
    QDBusReply<QStringList> r = m_iface.call("AvailableAlarmSounds");
    return r.isValid() ? r.value() : QStringList{};
}
QStringList SettingsClient::screenTimeoutOptions() {
    if (!ensureSystemPermission())
        return {};
    QDBusReply<QStringList> r = m_iface.call("ScreenTimeoutOptions");
    return r.isValid() ? r.value() : QStringList{};
}
int SettingsClient::screenTimeoutValue(const QString &option) {
    if (!ensureSystemPermission())
        return 0;
    QDBusReply<int> r = m_iface.call("ScreenTimeoutValue", option);
    return r.isValid() ? r.value() : 0;
}
QString SettingsClient::formatSoundName(const QString &path) {
    if (!ensureSystemPermission())
        return {};
    QDBusReply<QString> r = m_iface.call("FormatSoundName", path);
    return r.isValid() ? r.value() : QString{};
}
QString SettingsClient::assetUrl(const QString &relativePath) {
    if (!ensureSystemPermission())
        return {};
    QDBusReply<QString> r = m_iface.call("AssetUrl", relativePath);
    return r.isValid() ? r.value() : QString{};
}
QVariant SettingsClient::get(const QString &key, const QVariant &defaultValue) {
    if (!ensurePermissionForKey(key))
        return defaultValue;
    QDBusReply<QDBusVariant> r =
        m_iface.call("Get", key, QVariant::fromValue(QDBusVariant(defaultValue)));
    return r.isValid() ? r.value().variant() : defaultValue;
}
void SettingsClient::set(const QString &key, const QVariant &value) {
    if (!ensurePermissionForKey(key))
        return;
    auto r = m_iface.call("Set", key, QVariant::fromValue(QDBusVariant(value)));
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[SettingsClient] Set failed:" << r.errorMessage();
}
void SettingsClient::sync() {

    if (!ensureSystemPermission()) {
        if (!ensureStoragePermission())
            return;
    }
    auto r = m_iface.call("Sync");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[SettingsClient] Sync failed:" << r.errorMessage();
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
    m_state = state;
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

DisplayClient::DisplayClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Display",
              "org.marathonos.Shell.Display1", QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid())
        qWarning() << "[DisplayClient] DBus interface invalid:" << m_iface.lastError().message();

    m_startTimer.start();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Display",
                                          "org.marathonos.Shell.Display1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    refresh();
}

bool DisplayClient::ensureSystemPermission() {
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
    QTimer::singleShot(750, this, &DisplayClient::refresh);
    return false;
}

void DisplayClient::refresh() {
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
                qWarning() << "[DisplayClient] Initial GetState failed:" << r.error().name()
                           << r.error().message();
            }
            if (m_refreshRetryCount < 40) {
                const int backoffMs = qMin(2000, 250 * (1 << qMin(m_refreshRetryCount / 8, 3)));
                ++m_refreshRetryCount;
                QTimer::singleShot(backoffMs, this, &DisplayClient::refresh);
            } else if (!isAccessDenied(r.error())) {
                qWarning() << "[DisplayClient] GetState failed:" << r.error().message();
            }
            return;
        }

        m_refreshRetryCount = 0;
        if (!m_loggedFirstSync && debugEnabled()) {
            m_loggedFirstSync = true;
            qWarning() << "[DisplayClient] First sync after" << m_startTimer.elapsed()
                       << "ms brightness=" << r.value().value("brightness").toDouble()
                       << "rotationLocked=" << r.value().value("rotationLocked").toBool();
        }
        onStateChanged(r.value());
    });
}

void DisplayClient::onStateChanged(const QVariantMap &state) {
    m_state = state;
    emit stateChanged();
}

bool DisplayClient::available() const {
    return m_state.value("available").toBool();
}
bool DisplayClient::autoBrightnessEnabled() const {
    return m_state.value("autoBrightnessEnabled").toBool();
}
void DisplayClient::setAutoBrightnessEnabled(bool enabled) {
    auto r = m_iface.call("SetAutoBrightness", enabled);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetAutoBrightness failed:" << r.errorMessage();
}
bool DisplayClient::rotationLocked() const {
    return m_state.value("rotationLocked").toBool();
}
void DisplayClient::setRotationLocked(bool locked) {
    auto r = m_iface.call("SetRotationLock", locked);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetRotationLock failed:" << r.errorMessage();
}
int DisplayClient::screenTimeout() const {
    return m_state.value("screenTimeout").toInt();
}
void DisplayClient::setScreenTimeout(int seconds) {
    auto r = m_iface.call("SetScreenTimeout", seconds);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetScreenTimeout failed:" << r.errorMessage();
}
QString DisplayClient::screenTimeoutString() const {
    return m_state.value("screenTimeoutString").toString();
}
double DisplayClient::brightness() const {
    return m_state.value("brightness").toDouble();
}
void DisplayClient::setBrightness(double v) {
    auto r = m_iface.call("SetBrightness", v);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetBrightness failed:" << r.errorMessage();
}
bool DisplayClient::nightLightEnabled() const {
    return m_state.value("nightLightEnabled").toBool();
}
void DisplayClient::setNightLightEnabled(bool enabled) {
    auto r = m_iface.call("SetNightLightEnabled", enabled);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetNightLightEnabled failed:" << r.errorMessage();
}
int DisplayClient::nightLightTemperature() const {
    return m_state.value("nightLightTemperature").toInt();
}
void DisplayClient::setNightLightTemperature(int t) {
    auto r = m_iface.call("SetNightLightTemperature", t);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetNightLightTemperature failed:" << r.errorMessage();
}
QString DisplayClient::nightLightSchedule() const {
    return m_state.value("nightLightSchedule").toString();
}
void DisplayClient::setNightLightSchedule(const QString &s) {
    auto r = m_iface.call("SetNightLightSchedule", s);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetNightLightSchedule failed:" << r.errorMessage();
}

void DisplayClient::setScreenState(bool on) {
    auto r = m_iface.call("SetScreenState", on);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[DisplayClient] SetScreenState failed:" << r.errorMessage();
}

RemoteAudioStreamModel::RemoteAudioStreamModel(QObject *parent)
    : QAbstractListModel(parent) {}

int RemoteAudioStreamModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid())
        return 0;
    return m_streams.size();
}

QVariant RemoteAudioStreamModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_streams.size())
        return {};

    const QVariantMap s = m_streams.at(index.row()).toMap();
    switch (role) {
        case IdRole: return s.value("streamId");
        case NameRole: return s.value("name");
        case AppNameRole: return s.value("appName");
        case VolumeRole: return s.value("volume");
        case MutedRole: return s.value("muted");
        case MediaClassRole: return s.value("mediaClass");
        default: return {};
    }
}

QHash<int, QByteArray> RemoteAudioStreamModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole]         = "streamId";
    roles[NameRole]       = "name";
    roles[AppNameRole]    = "appName";
    roles[VolumeRole]     = "volume";
    roles[MutedRole]      = "muted";
    roles[MediaClassRole] = "mediaClass";
    return roles;
}

void RemoteAudioStreamModel::setStreams(const QVariantList &streams) {
    beginResetModel();
    m_streams = streams;
    endResetModel();
}

AudioClient::AudioClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Audio", "org.marathonos.Shell.Audio1",
              QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this))
    , m_streamModel(new RemoteAudioStreamModel(this)) {
    if (!m_iface.isValid())
        qWarning() << "[AudioClient] DBus interface invalid:" << m_iface.lastError().message();

    m_startTimer.start();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Audio",
                                          "org.marathonos.Shell.Audio1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    refresh();
}

bool AudioClient::ensureSystemPermission() {
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
    QTimer::singleShot(750, this, &AudioClient::refresh);
    return false;
}

void AudioClient::refresh() {
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
                qWarning() << "[AudioClient] Initial GetState failed:" << r.error().name()
                           << r.error().message();
            }
            if (m_refreshRetryCount < 40) {
                const int backoffMs = qMin(2000, 250 * (1 << qMin(m_refreshRetryCount / 8, 3)));
                ++m_refreshRetryCount;
                QTimer::singleShot(backoffMs, this, &AudioClient::refresh);
            } else if (!isAccessDenied(r.error())) {
                qWarning() << "[AudioClient] GetState failed:" << r.error().message();
            }
            return;
        }

        m_refreshRetryCount = 0;
        if (!m_loggedFirstSync && debugEnabled()) {
            m_loggedFirstSync = true;
            qWarning() << "[AudioClient] First sync after" << m_startTimer.elapsed()
                       << "ms volume=" << r.value().value("volume").toDouble()
                       << "muted=" << r.value().value("muted").toBool();
        }
        onStateChanged(r.value());
    });
}

QVariant AudioClient::v(const QString &k, const QVariant &fallback) const {
    return m_state.contains(k) ? m_state.value(k) : fallback;
}

void AudioClient::onStateChanged(const QVariantMap &state) {
    m_state = state;
    m_streamModel->setStreams(v("streams").toList());
    emit stateChanged();
}

bool AudioClient::available() const {
    return v("available").toBool();
}
double AudioClient::volume() const {
    return v("volume").toDouble();
}
bool AudioClient::muted() const {
    return v("muted").toBool();
}
bool AudioClient::perAppVolumeSupported() const {
    return v("perAppVolumeSupported").toBool();
}

QString AudioClient::audioProfile() const {
    return v("audioProfile").toString();
}

void AudioClient::setVolume(double v) {
    auto r = m_iface.call("SetVolume", v);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] SetVolume failed:" << r.errorMessage();
}
void AudioClient::setMuted(bool muted) {
    auto r = m_iface.call("SetMuted", muted);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] SetMuted failed:" << r.errorMessage();
}
void AudioClient::setStreamVolume(int streamId, double volume) {
    auto r = m_iface.call("SetStreamVolume", streamId, volume);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] SetStreamVolume failed:" << r.errorMessage();
}
void AudioClient::setStreamMuted(int streamId, bool muted) {
    auto r = m_iface.call("SetStreamMuted", streamId, muted);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] SetStreamMuted failed:" << r.errorMessage();
}
void AudioClient::refreshStreams() {
    auto r = m_iface.call("RefreshStreams");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] RefreshStreams failed:" << r.errorMessage();
}
void AudioClient::setDoNotDisturb(bool enabled) {
    auto r = m_iface.call("SetDoNotDisturb", enabled);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] SetDoNotDisturb failed:" << r.errorMessage();
}
void AudioClient::setAudioProfile(const QString &profile) {
    auto r = m_iface.call("SetAudioProfile", profile);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] SetAudioProfile failed:" << r.errorMessage();
}
void AudioClient::playRingtone() {
    auto r = m_iface.call("PlayRingtone");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] PlayRingtone failed:" << r.errorMessage();
}
void AudioClient::stopRingtone() {
    auto r = m_iface.call("StopRingtone");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] StopRingtone failed:" << r.errorMessage();
}
void AudioClient::playNotificationSound() {
    auto r = m_iface.call("PlayNotificationSound");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] PlayNotificationSound failed:" << r.errorMessage();
}
void AudioClient::playAlarmSound() {
    auto r = m_iface.call("PlayAlarmSound");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] PlayAlarmSound failed:" << r.errorMessage();
}
void AudioClient::stopAlarmSound() {
    auto r = m_iface.call("StopAlarmSound");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] StopAlarmSound failed:" << r.errorMessage();
}
void AudioClient::previewSound(const QString &soundPath) {
    auto r = m_iface.call("PreviewSound", soundPath);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] PreviewSound failed:" << r.errorMessage();
}
void AudioClient::vibratePattern(const QVariantList &pattern) {
    auto r = m_iface.call("VibratePattern", pattern);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[AudioClient] VibratePattern failed:" << r.errorMessage();
}

PowerClient::PowerClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Power", "org.marathonos.Shell.Power1",
              QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid())
        qWarning() << "[PowerClient] DBus interface invalid:" << m_iface.lastError().message();

    m_startTimer.start();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Power",
                                          "org.marathonos.Shell.Power1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    refresh();
}

bool PowerClient::ensureSystemPermission() {
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
    QTimer::singleShot(750, this, &PowerClient::refresh);
    return false;
}

QVariant PowerClient::v(const QString &k, const QVariant &fallback) const {
    return m_state.contains(k) ? m_state.value(k) : fallback;
}

void PowerClient::refresh() {
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
                qWarning() << "[PowerClient] Initial GetState failed:" << r.error().name()
                           << r.error().message();
            }
            if (m_refreshRetryCount < 40) {
                const int backoffMs = qMin(2000, 250 * (1 << qMin(m_refreshRetryCount / 8, 3)));
                ++m_refreshRetryCount;
                QTimer::singleShot(backoffMs, this, &PowerClient::refresh);
            } else if (!isAccessDenied(r.error())) {
                qWarning() << "[PowerClient] GetState failed:" << r.error().message();
            }
            return;
        }

        m_refreshRetryCount = 0;
        if (!m_loggedFirstSync && debugEnabled()) {
            m_loggedFirstSync = true;
            qWarning() << "[PowerClient] First sync after" << m_startTimer.elapsed()
                       << "ms batteryLevel=" << r.value().value("batteryLevel").toInt()
                       << "isCharging=" << r.value().value("isCharging").toBool();
        }
        onStateChanged(r.value());
    });
}

void PowerClient::onStateChanged(const QVariantMap &state) {
    m_state = state;
    emit stateChanged();
}

int PowerClient::batteryLevel() const {
    return v("batteryLevel").toInt();
}
bool PowerClient::isCharging() const {
    return v("isCharging").toBool();
}
bool PowerClient::isPluggedIn() const {
    return v("isPluggedIn").toBool();
}
bool PowerClient::isPowerSaveMode() const {
    return v("isPowerSaveMode").toBool();
}
int PowerClient::estimatedBatteryTime() const {
    return v("estimatedBatteryTime").toInt();
}
QString PowerClient::powerProfile() const {
    return v("powerProfile").toString();
}
bool PowerClient::powerProfilesSupported() const {
    return v("powerProfilesSupported").toBool();
}

void PowerClient::setPowerSaveMode(bool enabled) {
    auto r = m_iface.call("SetPowerSaveMode", enabled);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[PowerClient] SetPowerSaveMode failed:" << r.errorMessage();
}
void PowerClient::setPowerProfile(const QString &profile) {
    auto r = m_iface.call("SetPowerProfile", profile);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[PowerClient] SetPowerProfile failed:" << r.errorMessage();
}
void PowerClient::suspend() {
    auto r = m_iface.call("Suspend");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[PowerClient] Suspend failed:" << r.errorMessage();
}
void PowerClient::restart() {
    auto r = m_iface.call("Restart");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[PowerClient] Restart failed:" << r.errorMessage();
}
void PowerClient::shutdown() {
    auto r = m_iface.call("Shutdown");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[PowerClient] Shutdown failed:" << r.errorMessage();
}

NetworkClient::NetworkClient(const QString &appId, QObject *parent)
    : QObject(parent)
    , m_appId(appId)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Network",
              "org.marathonos.Shell.Network1", QDBusConnection::sessionBus())
    , m_permIface(makePermissionsIface(this)) {
    if (!m_iface.isValid())
        qWarning() << "[NetworkClient] DBus interface invalid:" << m_iface.lastError().message();

    m_startTimer.start();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Network",
                                          "org.marathonos.Shell.Network1", "StateChanged", this,
                                          SLOT(onStateChanged(QVariantMap)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Network",
                                          "org.marathonos.Shell.Network1", "NetworkError", this,
                                          SIGNAL(networkError(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Network",
                                          "org.marathonos.Shell.Network1", "ConnectionSuccess",
                                          this, SIGNAL(connectionSuccess()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Network",
                                          "org.marathonos.Shell.Network1", "ConnectionFailed", this,
                                          SIGNAL(connectionFailed(QString)));

    refresh();
}

bool NetworkClient::ensureNetworkPermission() {
    if (m_appId.isEmpty())
        return false;

    QDBusReply<bool> r = m_permIface.call("HasPermission", m_appId, "network");
    if (!r.isValid()) {
        if (!isAccessDenied(r.error()) && debugEnabled())
            qWarning() << "[NetworkClient] HasPermission(network) failed:" << r.error().message();
        return false;
    }

    if (r.value()) {
        m_permissionRequested = false;
        return true;
    }

    if (!m_permissionRequested) {
        m_permissionRequested = true;
        m_permIface.call("RequestPermission", m_appId, "network");
    }

    QTimer::singleShot(750, this, &NetworkClient::refresh);
    return false;
}

void NetworkClient::refresh() {
    if (m_refreshInFlight)
        return;
    m_refreshInFlight = true;
    m_iface.setTimeout(2000);

    if (!ensureNetworkPermission()) {
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
                qWarning() << "[NetworkClient] Initial GetState failed:" << r.error().name()
                           << r.error().message();
            }
            if (m_refreshRetryCount < 40) {
                const int backoffMs = qMin(2000, 250 * (1 << qMin(m_refreshRetryCount / 8, 3)));
                ++m_refreshRetryCount;
                QTimer::singleShot(backoffMs, this, &NetworkClient::refresh);
            } else if (!isAccessDenied(r.error())) {
                qWarning() << "[NetworkClient] GetState failed:" << r.error().message();
            }
            return;
        }

        m_refreshRetryCount = 0;
        if (!m_loggedFirstSync && debugEnabled()) {
            m_loggedFirstSync = true;
            const int networksCount =
                unwrapDbusVariantList(r.value().value("availableNetworks")).size();
            qWarning() << "[NetworkClient] First sync after" << m_startTimer.elapsed()
                       << "ms wifiEnabled=" << r.value().value("wifiEnabled").toBool()
                       << "wifiConnected=" << r.value().value("wifiConnected").toBool()
                       << "ssid=" << r.value().value("wifiSsid").toString()
                       << "availableNetworks=" << networksCount;
        }
        onStateChanged(r.value());
    });
}

QVariant NetworkClient::v(const QString &k, const QVariant &fallback) const {
    return m_state.contains(k) ? m_state.value(k) : fallback;
}

void NetworkClient::onStateChanged(const QVariantMap &state) {
    const QVariantMap prev          = m_state;
    QVariantMap       normalized    = state;
    normalized["availableNetworks"] = unwrapDbusVariantList(normalized.value("availableNetworks"));
    m_state                         = normalized;

    auto changed = [&](const QString &k) { return prev.value(k) != m_state.value(k); };

    if (changed("wifiEnabled"))
        emit wifiEnabledChanged();
    if (changed("wifiConnected"))
        emit wifiConnectedChanged();
    if (changed("wifiSsid"))
        emit wifiSsidChanged();
    if (changed("wifiSignalStrength"))
        emit wifiSignalStrengthChanged();
    if (changed("ethernetConnected"))
        emit ethernetConnectedChanged();
    if (changed("ethernetConnectionName"))
        emit ethernetConnectionNameChanged();
    if (changed("wifiAvailable"))
        emit wifiAvailableChanged();
    if (changed("bluetoothAvailable"))
        emit bluetoothAvailableChanged();
    if (changed("hotspotSupported"))
        emit hotspotSupportedChanged();
    if (changed("bluetoothEnabled"))
        emit bluetoothEnabledChanged();
    if (changed("airplaneModeEnabled"))
        emit airplaneModeEnabledChanged();
    if (changed("availableNetworks"))
        emit availableNetworksChanged();
}

bool NetworkClient::wifiEnabled() const {
    return v("wifiEnabled", false).toBool();
}
bool NetworkClient::wifiConnected() const {
    return v("wifiConnected", false).toBool();
}
QString NetworkClient::wifiSsid() const {
    return v("wifiSsid", "").toString();
}
int NetworkClient::wifiSignalStrength() const {
    return v("wifiSignalStrength", 0).toInt();
}
bool NetworkClient::ethernetConnected() const {
    return v("ethernetConnected", false).toBool();
}
QString NetworkClient::ethernetConnectionName() const {
    return v("ethernetConnectionName", "").toString();
}
bool NetworkClient::wifiAvailable() const {
    return v("wifiAvailable", false).toBool();
}
bool NetworkClient::bluetoothAvailable() const {
    return v("bluetoothAvailable", false).toBool();
}
bool NetworkClient::hotspotSupported() const {
    return v("hotspotSupported", false).toBool();
}
bool NetworkClient::bluetoothEnabled() const {
    return v("bluetoothEnabled", false).toBool();
}
bool NetworkClient::airplaneModeEnabled() const {
    return v("airplaneModeEnabled", false).toBool();
}
QVariantList NetworkClient::availableNetworks() const {
    return v("availableNetworks", QVariantList{}).toList();
}

void NetworkClient::enableWifi() {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("EnableWifi");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] EnableWifi failed:" << r.errorMessage();
}
void NetworkClient::disableWifi() {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("DisableWifi");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] DisableWifi failed:" << r.errorMessage();
}
void NetworkClient::toggleWifi() {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("ToggleWifi");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] ToggleWifi failed:" << r.errorMessage();
}
void NetworkClient::scanWifi() {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("ScanWifi");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] ScanWifi failed:" << r.errorMessage();
}
void NetworkClient::connectToNetwork(const QString &ssid, const QString &password) {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("ConnectToNetwork", ssid, password);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] ConnectToNetwork failed:" << r.errorMessage();
}
void NetworkClient::disconnectWifi() {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("DisconnectWifi");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] DisconnectWifi failed:" << r.errorMessage();
}
void NetworkClient::setAirplaneMode(bool enabled) {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("SetAirplaneMode", enabled);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] SetAirplaneMode failed:" << r.errorMessage();
}
void NetworkClient::createHotspot(const QString &ssid, const QString &password) {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("CreateHotspot", ssid, password);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] CreateHotspot failed:" << r.errorMessage();
}
void NetworkClient::stopHotspot() {
    if (!ensureNetworkPermission())
        return;
    auto r = m_iface.call("StopHotspot");
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[NetworkClient] StopHotspot failed:" << r.errorMessage();
}
bool NetworkClient::isHotspotActive() {
    if (!ensureNetworkPermission())
        return false;
    QDBusReply<bool> r = m_iface.call("IsHotspotActive");
    return r.isValid() ? r.value() : false;
}

void SmsClient::setConversations(const QVariantList &v) {
    m_conversations = v;
    emit conversationsChanged();
}

void SmsClient::refresh() {
    if (!ensurePermission()) {
        qWarning() << "[SmsClient] refresh: permission gate failed for" << m_appId;
        return;
    }
    QDBusReply<QVariantList> r = m_iface.call("GetConversations");
    if (!r.isValid()) {
        qWarning() << "[SmsClient] GetConversations failed:" << r.error().type()
                   << r.error().message();
        return;
    }
    qWarning() << "[SmsClient] refresh -> conversations:" << r.value().size();
    setConversations(r.value());
}

void SmsClient::sendMessage(const QString &recipient, const QString &text) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("SendMessage", recipient, text);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[SmsClient] SendMessage failed:" << r.errorMessage();
}

QVariantList SmsClient::getMessages(const QString &conversationId) {
    if (!ensurePermission())
        return {};
    QDBusReply<QVariantList> r = m_iface.call("GetMessages", conversationId);
    if (!r.isValid()) {
        qWarning() << "[SmsClient] GetMessages failed:" << r.error().message();
        return {};
    }
    return r.value();
}

void SmsClient::deleteConversation(const QString &conversationId) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("DeleteConversation", conversationId);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[SmsClient] DeleteConversation failed:" << r.errorMessage();
}

void SmsClient::markAsRead(const QString &conversationId) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("MarkAsRead", conversationId);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[SmsClient] MarkAsRead failed:" << r.errorMessage();
}

QString SmsClient::generateConversationId(const QString &number) {
    if (!ensurePermission())
        return {};
    QDBusReply<QString> r = m_iface.call("GenerateConversationId", number);
    if (!r.isValid()) {
        qWarning() << "[SmsClient] GenerateConversationId failed:" << r.error().message();
        return {};
    }
    return r.value();
}

void SmsClient::simulateIncomingSMS(const QString &sender, const QString &message) {
    if (!ensurePermission())
        return;
    auto r = m_iface.call("SimulateIncomingSMS", sender, message);
    if (r.type() == QDBusMessage::ErrorMessage)
        qWarning() << "[SmsClient] SimulateIncomingSMS failed:" << r.errorMessage();
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
}

SystemStatusStoreClient::SystemStatusStoreClient(PowerClient   *powerClient,
                                                 NetworkClient *networkClient, QObject *parent)
    : QObject(parent)
    , m_powerClient(powerClient)
    , m_networkClient(networkClient) {
    refreshPower();
    refreshNetwork();
    if (m_powerClient) {
        connect(m_powerClient, &PowerClient::stateChanged, this, [this]() { refreshPower(); });
    }
    if (m_networkClient) {
        connect(m_networkClient, &NetworkClient::wifiConnectedChanged, this,
                [this]() { refreshNetwork(); });
        connect(m_networkClient, &NetworkClient::wifiSsidChanged, this,
                [this]() { refreshNetwork(); });
    }
}

void SystemStatusStoreClient::refreshPower() {
    if (!m_powerClient) {
        setBatteryLevel(0);
        return;
    }
    setBatteryLevel(m_powerClient->batteryLevel());
}

void SystemStatusStoreClient::refreshNetwork() {
    if (!m_networkClient) {
        setWifiConnected(false);
        setWifiNetwork(QString());
        return;
    }
    setWifiConnected(m_networkClient->wifiConnected());
    setWifiNetwork(m_networkClient->wifiSsid());
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

SystemControlStoreClient::SystemControlStoreClient(NetworkClient   *networkClient,
                                                   BluetoothClient *bluetoothClient,
                                                   DisplayClient   *displayClient,
                                                   SettingsClient  *settingsClient,
                                                   AudioClient *audioClient, QObject *parent)
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
        connect(m_networkClient, &NetworkClient::wifiEnabledChanged, this,
                [this]() { refreshNetwork(); });
        connect(m_networkClient, &NetworkClient::airplaneModeEnabledChanged, this,
                [this]() { refreshNetwork(); });
    }
    if (m_bluetoothClient) {
        connect(m_bluetoothClient, &BluetoothClient::stateChanged, this,
                [this]() { refreshBluetooth(); });
    }
    if (m_displayClient) {
        connect(m_displayClient, &DisplayClient::stateChanged, this,
                [this]() { refreshDisplay(); });
    }
    if (m_settingsClient) {
        connect(m_settingsClient, &SettingsClient::dndEnabledChanged, this,
                [this]() { refreshSettings(); });
    }
    if (m_audioClient) {
        connect(m_audioClient, &AudioClient::stateChanged, this, [this]() { refreshAudio(); });
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
    setIsWifiOn(m_networkClient->wifiEnabled());
    setIsAirplaneModeOn(m_networkClient->airplaneModeEnabled());
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
    setIsRotationLocked(m_displayClient->rotationLocked());
    setBrightnessValue(
        static_cast<int>(std::round(std::clamp(m_displayClient->brightness(), 0.0, 1.0) * 100.0)));
}

void SystemControlStoreClient::refreshSettings() {
    if (!m_settingsClient) {
        setIsDndMode(false);
        return;
    }
    setIsDndMode(m_settingsClient->dndEnabled());
}

void SystemControlStoreClient::refreshAudio() {
    if (!m_audioClient) {
        setVolumeValue(50);
        return;
    }
    setVolumeValue(
        static_cast<int>(std::round(std::clamp(m_audioClient->volume(), 0.0, 1.0) * 100.0)));
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
        for (const QVariant &a : actionList) {
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

SensorClient::SensorClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Sensor",
              "org.marathonos.Shell.Sensor1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[SensorClient] DBus interface invalid:" << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Sensor",
                                          "org.marathonos.Shell.Sensor1", "ProximityChanged", this,
                                          SIGNAL(proximityChanged()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Sensor",
                                          "org.marathonos.Shell.Sensor1", "AmbientLightChanged",
                                          this, SIGNAL(ambientLightChanged()));

    refresh();
}

void SensorClient::refresh() {
    if (m_iface.isValid()) {
        bool avail = m_iface.property("available").toBool();
        bool prox  = m_iface.property("proximityNear").toBool();
        int  light = m_iface.property("ambientLight").toInt();

        if (avail != m_available) {
            m_available = avail;
            emit availableChanged();
        }
        if (prox != m_proximityNear) {
            m_proximityNear = prox;
            emit proximityChanged();
        }
        if (light != m_ambientLight) {
            m_ambientLight = light;
            emit ambientLightChanged();
        }
    }
}

LocationClient::LocationClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Location",
              "org.marathonos.Shell.Location1", QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[LocationClient] DBus interface invalid:" << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Location",
                                          "org.marathonos.Shell.Location1", "LocationChanged", this,
                                          SLOT(updateLocation(QVariantMap)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Location",
                                          "org.marathonos.Shell.Location1", "activeChanged", this,
                                          SIGNAL(activeChanged()));
    refresh();
}

void LocationClient::refresh() {
    if (!m_iface.isValid())
        return;

    // The shell-side service exposes availability/active state as
    // methods (IsAvailable/IsActive), not DBus properties, so a
    // m_iface.property("available") read silently returns an invalid
    // QVariant and we'd never know the fix landed.
    const auto availArgs  = m_iface.call("IsAvailable").arguments();
    const auto activeArgs = m_iface.call("IsActive").arguments();
    const bool avail      = !availArgs.isEmpty() ? availArgs.at(0).toBool() : false;
    const bool active     = !activeArgs.isEmpty() ? activeArgs.at(0).toBool() : false;

    if (avail != m_available) {
        m_available = avail;
        emit availableChanged();
    }
    if (active != m_active) {
        m_active = active;
        emit activeChanged();
    }
    const auto locArgs = m_iface.call("GetLocation").arguments();
    if (!locArgs.isEmpty()) {
        // a{sv} arrives as a QDBusArgument blob inside the QVariant;
        // normalize through the same demarshal helpers other Marathon
        // IPC clients use so we get a real QVariantMap.
        const QVariantMap loc = normalizeDbusVariantDeep(locArgs.at(0)).toMap();
        updateLocation(loc);
    }
}

void LocationClient::updateLocation(const QVariantMap &loc) {
    if (loc.isEmpty())
        return;

    m_latitude  = loc.value("latitude").toDouble();
    m_longitude = loc.value("longitude").toDouble();
    m_accuracy  = loc.value("accuracy").toDouble();
    m_altitude  = loc.value("altitude").toDouble();
    m_speed     = loc.value("speed").toDouble();
    m_heading   = loc.value("heading").toDouble();
    m_timestamp = loc.value("timestamp").toLongLong();
    emit locationChanged();
}

void LocationClient::start() {
    m_iface.call("Start");
    // Re-pull state after Start so a freshly-active fix shows up
    // immediately instead of waiting for the next LocationChanged
    // signal (which can be a 25 s Geoclue heartbeat).
    refresh();
}

void LocationClient::stop() {
    m_iface.call("Stop");
}

AlarmClient::AlarmClient(QObject *parent)
    : QObject(parent)
    , m_iface("org.marathonos.Shell", "/org/marathonos/Shell/Alarm", "org.marathonos.Shell.Alarm1",
              QDBusConnection::sessionBus()) {
    if (!m_iface.isValid())
        qWarning() << "[AlarmClient] DBus interface invalid:" << m_iface.lastError().message();

    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Alarm",
                                          "org.marathonos.Shell.Alarm1", "AlarmsChanged", this,
                                          SLOT(onAlarmsChanged()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Alarm",
                                          "org.marathonos.Shell.Alarm1", "ActiveAlarmsChanged",
                                          this, SLOT(onActiveAlarmsChanged()));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Alarm",
                                          "org.marathonos.Shell.Alarm1", "AlarmTriggered", this,
                                          SIGNAL(alarmTriggered(QString, QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Alarm",
                                          "org.marathonos.Shell.Alarm1", "AlarmDismissed", this,
                                          SIGNAL(alarmDismissed(QString)));
    QDBusConnection::sessionBus().connect("org.marathonos.Shell", "/org/marathonos/Shell/Alarm",
                                          "org.marathonos.Shell.Alarm1", "AlarmSnoozed", this,
                                          SIGNAL(alarmSnoozed(QString, int)));

    refresh();
}

void AlarmClient::refresh() {
    if (m_iface.isValid()) {
        onAlarmsChanged();
        onActiveAlarmsChanged();
    }
}

void AlarmClient::onAlarmsChanged() {
    QDBusReply<QVariantList> r = m_iface.call("GetAlarms");
    if (r.isValid()) {
        m_alarms = r.value();
        emit alarmsChanged();
    }
}

void AlarmClient::onActiveAlarmsChanged() {
    QDBusReply<QVariantList> r = m_iface.call("GetActiveAlarms");
    if (r.isValid()) {
        m_activeAlarms = r.value();
        emit activeAlarmsChanged();
    }
}

QString AlarmClient::createAlarm(const QString &time, const QString &label,
                                 const QList<int> &repeat, const QVariantMap &options) {
    QDBusReply<QString> r =
        m_iface.call("CreateAlarm", time, label, QVariant::fromValue(repeat), options);
    return r.isValid() ? r.value() : QString();
}

bool AlarmClient::updateAlarm(const QString &id, const QVariantMap &updates) {
    QDBusReply<bool> r = m_iface.call("UpdateAlarm", id, updates);
    return r.isValid() && r.value();
}

bool AlarmClient::deleteAlarm(const QString &id) {
    QDBusReply<bool> r = m_iface.call("DeleteAlarm", id);
    return r.isValid() && r.value();
}

bool AlarmClient::enableAlarm(const QString &id) {
    QDBusReply<bool> r = m_iface.call("EnableAlarm", id);
    return r.isValid() && r.value();
}

bool AlarmClient::disableAlarm(const QString &id) {
    QDBusReply<bool> r = m_iface.call("DisableAlarm", id);
    return r.isValid() && r.value();
}

bool AlarmClient::snoozeAlarm(const QString &id) {
    QDBusReply<bool> r = m_iface.call("SnoozeAlarm", id);
    return r.isValid() && r.value();
}

bool AlarmClient::dismissAlarm(const QString &id) {
    QDBusReply<bool> r = m_iface.call("DismissAlarm", id);
    return r.isValid() && r.value();
}

void AlarmClient::stopAll() {
    m_iface.call("StopAll");
}

void AlarmClient::triggerAlarmNow(const QString &label) {
    m_iface.call("TriggerAlarmNow", label);
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
        m_state = r.value();
        emit stateChanged();
    }
}

void UpdateClient::onStateChanged(const QVariantMap &state) {
    m_state = state;
    emit stateChanged();
}

void UpdateClient::checkNow() {
    m_iface.call("CheckNow");
}

void UpdateClient::openInBrowser() {
    m_iface.call("OpenInBrowser");
}

void UpdateClient::setChannel(const QString &channel) {
    m_iface.call("SetChannel", channel);
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
    refresh();
}

void DavClient::refresh() {
    refreshAccounts();
    refreshState();
}

void DavClient::refreshAccounts() {
    QDBusReply<QVariantList> r = m_iface.call("ListAccounts");
    if (r.isValid()) {
        m_accounts = r.value();
        emit accountsChanged();
    }
}

void DavClient::refreshState() {
    QDBusReply<QVariantMap> r = m_iface.call("GetState");
    if (r.isValid()) {
        m_state = r.value();
        emit stateChanged();
    }
}

void DavClient::onAccountsChanged() {
    refreshAccounts();
}

void DavClient::onStateChanged(const QVariantMap &state) {
    m_state = state;
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
        m_state = r.value();
        emit stateChanged();
    }
}

void AppStoreClient::onStateChanged(const QVariantMap &state) {
    m_state = state;
    emit stateChanged();
}

void AppStoreClient::refreshCatalog() {
    m_iface.call("RefreshCatalog");
}

// Each catalog entry arrives as a QVariantList<QDBusArgument>; QML's
// JS engine can't see the inner QVariantMap keys until we qdbus_cast
// them back. We pull the raw reply via QDBusReply<QVariantList> (so
// QDBus does the type coercion) and then run the result through
// normalizeListDeep — same path ContactsClient.setContacts uses for
// the same problem. Without this, every modelData.name read in QML
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
