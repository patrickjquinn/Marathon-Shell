// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The D-Bus side of Sailfish.Share (see keelshare.h). The contract, as the
// system share dialog (sailfish-share, org.sailfishos.share) uses it:
//   - an app opens the dialog with org.sailfishos.share.share(a{sv}) on
//     path "/" of the session bus service org.sailfishos.share; the map is
//     the ShareAction's configuration: "resources" (av: file paths, or maps
//     with "name" and "data", and optional "type" / "linkTitle"),
//     "mimeType" (s), "title" (s), "selectedTransferMethodInfo" (a{sv});
//   - an app receives shares with a share method declared in its desktop
//     entry (X-Share-Methods and [X-Share Method <name>]); the dialog calls
//     org.sailfishos.share.share(a{sv}) with the same configuration on the
//     app's /share/<name> object, under the app's Sailjail D-Bus name. Files
//     may arrive as maps with "name" and a "fileDescriptor" (h).

#include "keelshare.h"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusUnixFileDescriptor>
#include <QDBusVariant>
#include <QDBusVirtualObject>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>

#include <unistd.h>

Q_LOGGING_CATEGORY(lcKeelShare, "keel.share", QtWarningMsg)

namespace {

const QString ShareService = QStringLiteral("org.sailfishos.share");
const QString ShareInterface = QStringLiteral("org.sailfishos.share");

// D-Bus values to plain QVariants (maps, lists, strings, descriptors).
QVariant plain(const QVariant &value)
{
    if (value.metaType() == QMetaType::fromType<QDBusVariant>())
        return plain(value.value<QDBusVariant>().variant());
    if (value.metaType() != QMetaType::fromType<QDBusArgument>())
        return value;
    const auto arg = value.value<QDBusArgument>();
    switch (arg.currentType()) {
    case QDBusArgument::MapType: {
        QVariantMap map;
        arg.beginMap();
        while (!arg.atEnd()) {
            QString key;
            QVariant item;
            arg.beginMapEntry();
            arg >> key >> item;
            arg.endMapEntry();
            map.insert(key, plain(item));
        }
        arg.endMap();
        return map;
    }
    case QDBusArgument::ArrayType: {
        QVariantList list;
        arg.beginArray();
        while (!arg.atEnd()) {
            QVariant item;
            arg >> item;
            list.append(plain(item));
        }
        arg.endArray();
        return list;
    }
    default:
        return arg.asVariant();
    }
}

// A resource as the dialog expects it: local files as absolute paths.
QVariant outgoingResource(const QVariant &value)
{
    if (value.metaType() == QMetaType::fromType<QUrl>()) {
        const QUrl url = value.toUrl();
        return url.isLocalFile() ? url.toLocalFile() : url.toString();
    }
    if (value.metaType() == QMetaType::fromType<QString>()) {
        const QString text = value.toString();
        if (text.startsWith(QLatin1String("file://")))
            return QUrl(text).toLocalFile();
        return text;
    }
    if (value.canConvert<QVariantMap>() && value.metaType() != QMetaType::fromType<QString>()) {
        QVariantMap map = value.toMap();
        for (auto it = map.begin(); it != map.end(); ++it) {
            if (it.value().metaType() == QMetaType::fromType<QUrl>())
                it.value() = it.value().toUrl().toString();
        }
        return map;
    }
    return value;
}

class ShareObject : public QDBusVirtualObject
{
public:
    explicit ShareObject(ShareProvider *provider)
        : QDBusVirtualObject(provider)
        , m_provider(provider)
    {
    }

    QString introspect(const QString &) const override
    {
        return QStringLiteral("<interface name=\"org.sailfishos.share\">"
                              "<method name=\"share\"><arg name=\"configuration\" type=\"a{sv}\" direction=\"in\"/>"
                              "</method></interface>");
    }

    bool handleMessage(const QDBusMessage &message, const QDBusConnection &connection) override
    {
        if (message.interface() != ShareInterface || message.member() != QLatin1String("share"))
            return false;
        const QVariantMap configuration = plain(message.arguments().value(0)).toMap();
        const QString error = m_provider->share(configuration);
        if (error.isEmpty())
            connection.send(message.createReply());
        else
            connection.send(message.createErrorReply(error, QStringLiteral("Share configuration not accepted")));
        return true;
    }

private:
    ShareProvider *m_provider;
};

} // namespace

ShareResource::ShareResource(ResourceType type, QString name, QString data, QString filePath, QObject *parent)
    : QObject(parent)
    , m_type(type)
    , m_name(std::move(name))
    , m_data(std::move(data))
    , m_filePath(std::move(filePath))
{
}

ShareProvider::ShareProvider(QObject *parent)
    : QObject(parent)
{
}

ShareProvider::~ShareProvider()
{
    unregisterObject();
    if (m_nameRegistered)
        QDBusConnection::sessionBus().unregisterService(serviceName());
    for (const QString &file : std::as_const(m_receivedFiles)) {
        QFile::remove(file);
        QDir().rmdir(QFileInfo(file).absolutePath());
    }
}

QString ShareProvider::serviceName()
{
    QString organization = QCoreApplication::organizationName();
    if (organization.isEmpty())
        organization = QCoreApplication::organizationDomain();
    const QString application = QCoreApplication::applicationName();
    return organization.isEmpty() ? application : organization + QLatin1Char('.') + application;
}

void ShareProvider::setMethod(const QString &method)
{
    if (m_method == method)
        return;
    m_method = method;
    if (m_complete)
        registerObject();
    emit methodChanged();
}

void ShareProvider::setRegisterName(bool registerName)
{
    if (m_registerName == registerName)
        return;
    m_registerName = registerName;
    if (m_complete && registerName && !m_nameRegistered)
        m_nameRegistered = QDBusConnection::sessionBus().registerService(serviceName());
    emit registerNameChanged();
}

void ShareProvider::setCapabilities(const QStringList &capabilities)
{
    if (m_capabilities == capabilities)
        return;
    m_capabilities = capabilities;
    emit capabilitiesChanged();
}

void ShareProvider::componentComplete()
{
    m_complete = true;
    registerObject();
    if (m_registerName && !m_nameRegistered) {
        m_nameRegistered = QDBusConnection::sessionBus().registerService(serviceName());
        if (!m_nameRegistered)
            qCWarning(lcKeelShare) << "cannot register" << serviceName() << "on the session bus";
    }
}

void ShareProvider::registerObject()
{
    unregisterObject();
    if (m_method.isEmpty())
        return;
    // Method names are path elements.
    static const QRegularExpression valid(QStringLiteral("^[A-Za-z0-9_]+$"));
    if (!valid.match(m_method).hasMatch()) {
        qCWarning(lcKeelShare) << "share method" << m_method << "is not a valid D-Bus path element";
        return;
    }
    const QString path = QStringLiteral("/share/") + m_method;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qCWarning(lcKeelShare).noquote() << "no session bus (" + bus.lastError().message() + "):"
                                         << "the share target" << path << "is not offered";
        return;
    }
    if (bus.objectRegisteredAt(path)) {
        qCWarning(lcKeelShare) << "cannot register" << path << "on the session bus:"
                               << "another ShareProvider uses the method name" << m_method;
        return;
    }
    auto* object = new ShareObject(this);
    if (!bus.registerVirtualObject(path, object)) {
        qCWarning(lcKeelShare) << "cannot register" << path << "on the session bus:"
                               << bus.lastError().message();
        delete object;
        return;
    }
    m_registeredPath = path;
}

void ShareProvider::unregisterObject()
{
    if (m_registeredPath.isEmpty())
        return;
    QDBusConnection::sessionBus().unregisterObject(m_registeredPath);
    m_registeredPath.clear();
}

bool ShareProvider::accepts(const QString &mimeType) const
{
    if (m_capabilities.isEmpty() || m_capabilities.contains(QStringLiteral("*")) || mimeType.isEmpty())
        return true;
    for (const QString &capability : m_capabilities) {
        if (capability == mimeType || capability == QLatin1String("*/*"))
            return true;
        if (capability.endsWith(QLatin1String("/*"))
            && mimeType.startsWith(capability.left(capability.size() - 1)))
            return true;
        // A wildcard configuration ("image/*") matches a capability of that kind.
        if (mimeType.endsWith(QLatin1String("/*")) && capability.startsWith(mimeType.left(mimeType.size() - 1)))
            return true;
    }
    return false;
}

std::unique_ptr<ShareResource> ShareProvider::resourceFrom(const QVariant &value, QString *error)
{
    if (value.metaType() == QMetaType::fromType<QString>()) {
        const QString path = value.toString();
        if (!QFileInfo(path).isAbsolute()) {
            *error = QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs");
            return nullptr;
        }
        return std::make_unique<ShareResource>(ShareResource::FilePathType, QFileInfo(path).fileName(), QString(),
                                               path, nullptr);
    }
    const QVariantMap map = value.toMap();
    const QString name = map.value(QStringLiteral("name")).toString();
    const QVariant fd = map.value(QStringLiteral("fileDescriptor"));
    if (fd.metaType() == QMetaType::fromType<QDBusUnixFileDescriptor>()) {
        // A file handed over as a descriptor: copied into the app's cache,
        // where the app may read it.
        const auto descriptor = fd.value<QDBusUnixFileDescriptor>();
        QFile source;
        if (!descriptor.isValid() || !source.open(dup(descriptor.fileDescriptor()), QIODevice::ReadOnly,
                                                  QFileDevice::AutoCloseHandle)) {
            *error = QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs");
            return nullptr;
        }
        if (!QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)))
            qCWarning(lcKeelShare) << "cannot create the cache directory";
        QTemporaryDir created(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                              + QStringLiteral("/sailfish-share_XXXXXX"));
        if (!created.isValid()) {
            *error = QStringLiteral("org.freedesktop.DBus.Error.Failed");
            return nullptr;
        }
        created.setAutoRemove(false);
        const QString safeName = name.isEmpty() ? QStringLiteral("shared") : QFileInfo(name).fileName();
        const QString path = created.filePath(safeName);
        QFile target(path);
        if (!target.open(QIODevice::WriteOnly) || target.write(source.readAll()) < 0) {
            *error = QStringLiteral("org.freedesktop.DBus.Error.Failed");
            return nullptr;
        }
        m_receivedFiles.append(path);
        return std::make_unique<ShareResource>(ShareResource::FilePathType, safeName, QString(), path, nullptr);
    }
    if (!map.contains(QStringLiteral("data")) && !map.contains(QStringLiteral("status"))) {
        *error = QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs");
        return nullptr;
    }
    // Link shares (the browser) carry the URL as "status".
    const QString data = map.contains(QStringLiteral("data")) ? map.value(QStringLiteral("data")).toString()
                                                               : map.value(QStringLiteral("status")).toString();
    return std::make_unique<ShareResource>(ShareResource::StringDataType, name, data, QString(), nullptr);
}

QString ShareProvider::share(const QVariantMap &configuration)
{
    if (!accepts(configuration.value(QStringLiteral("mimeType")).toString()))
        return QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs");
    const QVariant resources = configuration.value(QStringLiteral("resources"));
    const QVariantList list = resources.metaType() == QMetaType::fromType<QVariantList>()
        ? resources.toList()
        : QVariantList { resources };
    std::vector<std::unique_ptr<ShareResource>> made;
    for (const QVariant &value : list) {
        QString error;
        std::unique_ptr<ShareResource> resource = resourceFrom(value, &error);
        if (!resource)
            return error;
        made.push_back(std::move(resource));
    }
    if (made.empty())
        return QStringLiteral("org.freedesktop.DBus.Error.InvalidArgs");
    // The previous share's resources go; these live until the next one (or
    // the provider), owned by the provider.
    qDeleteAll(m_resources);
    m_resources.clear();
    QVariantList shared;
    for (std::unique_ptr<ShareResource> &resource : made) {
        resource->setParent(this);
        m_resources.append(resource.get());
        shared.append(QVariant::fromValue<QObject *>(resource.release()));
    }
    emit triggered(shared);
    return QString();
}

KeelShareService::KeelShareService(QObject *parent)
    : QObject(parent)
{
}

bool KeelShareService::available() const
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || !bus.interface())
        return false;
    if (bus.interface()->isServiceRegistered(ShareService).value())
        return true;
    return bus.interface()->activatableServiceNames().value().contains(ShareService);
}

bool KeelShareService::share(const QVariantMap &configuration)
{
    QVariantMap config = configuration;
    QVariantList resources;
    const QVariantList list = configuration.value(QStringLiteral("resources")).toList();
    for (const QVariant &value : list)
        resources.append(outgoingResource(value));
    config.insert(QStringLiteral("resources"), resources);
    QDBusMessage call = QDBusMessage::createMethodCall(ShareService, QStringLiteral("/"), ShareInterface,
                                                       QStringLiteral("share"));
    call.setArguments({ config });
    if (!QDBusConnection::sessionBus().send(call)) {
        qCWarning(lcKeelShare) << "Unable to call org.sailfishos.share.share():"
                               << QDBusConnection::sessionBus().lastError().message();
        return false;
    }
    return true;
}
