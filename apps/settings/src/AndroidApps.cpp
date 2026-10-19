#include "AndroidApps.h"

#include <QCollator>
#include <QDBusArgument>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusServiceWatcher>
#include <QDBusVariant>
#include <QQmlEngine>

#include <algorithm>

namespace {
    const QString kService  = QStringLiteral("org.marathonos.Deckard");
    const QString kPath     = QStringLiteral("/org/marathonos/Deckard");
    const QString kDeckard  = QStringLiteral("org.marathonos.Deckard1");
    const QString kPackages = QStringLiteral("org.marathonos.Deckard1.Packages");

    // D-Bus containers inside variants arrive as QDBusArgument; QML wants maps and lists.
    QVariant plain(const QVariant &v) {
        if (v.userType() == qMetaTypeId<QDBusVariant>())
            return plain(v.value<QDBusVariant>().variant());
        if (v.userType() != qMetaTypeId<QDBusArgument>())
            return v;
        const QDBusArgument arg = v.value<QDBusArgument>();
        switch (arg.currentType()) {
        case QDBusArgument::MapType: {
            QVariantMap map;
            arg.beginMap();
            while (!arg.atEnd()) {
                arg.beginMapEntry();
                const QVariant key   = arg.asVariant();
                const QVariant value = arg.asVariant();
                arg.endMapEntry();
                map.insert(plain(key).toString(), plain(value));
            }
            arg.endMap();
            return map;
        }
        case QDBusArgument::ArrayType: {
            QVariantList list;
            arg.beginArray();
            while (!arg.atEnd())
                list.append(plain(arg.asVariant()));
            arg.endArray();
            return list;
        }
        case QDBusArgument::StructureType: {
            QVariantList list;
            arg.beginStructure();
            while (!arg.atEnd())
                list.append(plain(arg.asVariant()));
            arg.endStructure();
            return list;
        }
        default:
            return arg.asVariant();
        }
    }

    QVariant first(const QDBusMessage &reply) {
        return reply.arguments().isEmpty() ? QVariant() : plain(reply.arguments().constFirst());
    }

    bool ok(const QDBusMessage &reply) {
        return reply.type() == QDBusMessage::ReplyMessage;
    }
} // namespace

AndroidApps *AndroidApps::create(QQmlEngine *engine, QJSEngine *) {
    auto *apps = new AndroidApps(engine);
    QQmlEngine::setObjectOwnership(apps, QQmlEngine::CppOwnership);
    return apps;
}

AndroidApps::AndroidApps(QObject *parent)
    : QObject(parent)
    , m_bus(QDBusConnection::sessionBus()) {
    auto *watcher = new QDBusServiceWatcher(kService, m_bus, QDBusServiceWatcher::WatchForOwnerChange, this);
    connect(watcher, &QDBusServiceWatcher::serviceOwnerChanged, this, &AndroidApps::onOwnerChanged);
    m_bus.connect(kService, kPath, kDeckard, QStringLiteral("RuntimeChanged"), this,
                  SLOT(onRuntimeChanged(QVariantMap)));
    m_bus.connect(kService, kPath, kDeckard, QStringLiteral("AppChanged"), this, SLOT(onAppChanged(QString)));
    m_bus.connect(kService, kPath, kPackages, QStringLiteral("PackageChanged"), this,
                  SLOT(onPackageChanged(QString, QString)));
    m_bus.connect(kService, kPath, kPackages, QStringLiteral("Finished"), this,
                  SLOT(onFinished(QString, bool, QString, QString)));
    refresh();
}

bool AndroidApps::available() const {
    return m_available;
}

QVariantMap AndroidApps::runtime() const {
    return m_runtime;
}

QVariantList AndroidApps::apps() const {
    return m_apps;
}

QVariantMap AndroidApps::googleServices() const {
    return m_google;
}

void AndroidApps::setAvailable(bool available) {
    if (available == m_available)
        return;
    m_available = available;
    Q_EMIT availableChanged();
}

void AndroidApps::call(const QString &interface, const QString &method, const QVariantList &args, Reply reply) {
    QDBusMessage m = QDBusMessage::createMethodCall(kService, kPath, interface, method);
    m.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(m, 60000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, reply = std::move(reply)] {
        watcher->deleteLater();
        if (reply)
            reply(watcher->reply());
    });
}

void AndroidApps::refreshRuntime() {
    call(kDeckard, QStringLiteral("GetRuntime"), {}, [this](const QDBusMessage &r) {
        setAvailable(ok(r));
        if (ok(r))
            onRuntimeChanged(first(r).toMap());
    });
}

void AndroidApps::refresh() {
    refreshRuntime();
    call(kPackages, QStringLiteral("ListPackages"), {}, [this](const QDBusMessage &r) {
        if (!ok(r))
            return;
        QVariantList  apps;
        const QVariantList packages = first(r).toList();
        for (const QVariant &p : packages) {
            const QVariantMap package = p.toMap();
            const QString     pkg     = package.value(QStringLiteral("pkg")).toString();
            if (pkg.isEmpty() || package.value(QStringLiteral("system")).toBool())
                continue;
            const QString label = package.value(QStringLiteral("label")).toString();
            apps.append(QVariantMap{{QStringLiteral("pkg"), pkg},
                                    {QStringLiteral("id"), QStringLiteral("waydroid.") + pkg},
                                    {QStringLiteral("name"), label.isEmpty() ? pkg : label},
                                    {QStringLiteral("version"), package.value(QStringLiteral("versionName"))},
                                    {QStringLiteral("icon"), m_icons.value(pkg)}});
            if (!m_icons.contains(pkg))
                loadIcon(pkg);
        }
        QCollator collator;
        collator.setCaseSensitivity(Qt::CaseInsensitive);
        std::sort(apps.begin(), apps.end(), [&](const QVariant &a, const QVariant &b) {
            return collator.compare(a.toMap().value(QStringLiteral("name")).toString(),
                                    b.toMap().value(QStringLiteral("name")).toString()) < 0;
        });
        m_apps = apps;
        Q_EMIT appsChanged();
    });
}

void AndroidApps::loadIcon(const QString &pkg) {
    m_icons.insert(pkg, QString());
    call(kDeckard, QStringLiteral("AppIcon"), {pkg}, [this, pkg](const QDBusMessage &r) {
        const QString icon = ok(r) ? first(r).toString() : QString();
        if (icon.isEmpty())
            return;
        m_icons.insert(pkg, icon);
        for (QVariant &a : m_apps) {
            QVariantMap app = a.toMap();
            if (app.value(QStringLiteral("pkg")).toString() == pkg) {
                app.insert(QStringLiteral("icon"), icon);
                a = app;
            }
        }
        Q_EMIT appsChanged();
    });
}

void AndroidApps::act(const QString &action, const QString &pkg, const QString &method, const QVariantList &args) {
    call(kDeckard, method, args, [this, action, pkg](const QDBusMessage &r) {
        if (ok(r))
            Q_EMIT done(pkg, action);
        else
            Q_EMIT failed(pkg, action, r.errorMessage());
    });
}

void AndroidApps::start() {
    act(QStringLiteral("start"), QString(), QStringLiteral("Start"), {});
}

void AndroidApps::stop() {
    act(QStringLiteral("stop"), QString(), QStringLiteral("Stop"), {});
}

void AndroidApps::restart() {
    act(QStringLiteral("restart"), QString(), QStringLiteral("Restart"), {});
}

void AndroidApps::setStartAtLogin(bool enabled) {
    act(QStringLiteral("setStartAtLogin"), QString(), QStringLiteral("SetStartAtLogin"), {enabled});
}

void AndroidApps::resetAndroid() {
    call(kDeckard, QStringLiteral("ResetAndroid"), {}, [this](const QDBusMessage &r) {
        if (!ok(r)) {
            Q_EMIT failed(QString(), QStringLiteral("reset"), r.errorMessage());
            return;
        }
        // Android is stopped, so ListPackages can't say the apps are gone.
        m_apps.clear();
        m_icons.clear();
        Q_EMIT appsChanged();
        Q_EMIT done(QString(), QStringLiteral("reset"));
    });
}

void AndroidApps::loadApp(const QString &pkg) {
    call(kDeckard, QStringLiteral("GetApp"), {pkg}, [this, pkg](const QDBusMessage &r) {
        if (!ok(r)) {
            Q_EMIT failed(pkg, QStringLiteral("loadApp"), r.errorMessage());
            return;
        }
        QVariantMap app = first(r).toMap();
        app.insert(QStringLiteral("icon"), m_icons.value(pkg));
        Q_EMIT appLoaded(pkg, app);
    });
    if (!m_icons.contains(pkg))
        loadIcon(pkg);
}

void AndroidApps::setPermission(const QString &pkg, const QString &permission, bool granted) {
    act(QStringLiteral("setPermission"), pkg, QStringLiteral("SetPermission"), {pkg, permission, granted});
}

void AndroidApps::loadPermissionApps(const QString &permission) {
    call(kDeckard, QStringLiteral("GetPermissionApps"), {permission}, [this, permission](const QDBusMessage &r) {
        QVariantList apps = ok(r) ? first(r).toList() : QVariantList();
        for (QVariant &a : apps) {
            QVariantMap app   = a.toMap();
            const QString pkg = app.value(QStringLiteral("pkg")).toString();
            app.insert(QStringLiteral("icon"), m_icons.value(pkg));
            a = app;
        }
        Q_EMIT permissionAppsLoaded(permission, apps);
    });
}

void AndroidApps::setNotifications(const QString &pkg, bool enabled) {
    act(QStringLiteral("setNotifications"), pkg, QStringLiteral("SetNotifications"), {pkg, enabled});
}

void AndroidApps::setOpenLinks(const QString &pkg, bool enabled) {
    act(QStringLiteral("setOpenLinks"), pkg, QStringLiteral("SetOpenLinks"), {pkg, enabled});
}

void AndroidApps::setBattery(const QString &pkg, const QString &mode) {
    act(QStringLiteral("setBattery"), pkg, QStringLiteral("SetBattery"), {pkg, mode});
}

void AndroidApps::forceStop(const QString &pkg) {
    act(QStringLiteral("forceStop"), pkg, QStringLiteral("ForceStop"), {pkg});
}

void AndroidApps::clearCache(const QString &pkg) {
    act(QStringLiteral("clearCache"), pkg, QStringLiteral("ClearCache"), {pkg});
}

void AndroidApps::clearData(const QString &pkg) {
    act(QStringLiteral("clearData"), pkg, QStringLiteral("ClearData"), {pkg});
}

void AndroidApps::uninstall(const QString &pkg) {
    m_uninstalling.insert(pkg);
    call(kPackages, QStringLiteral("UninstallPackage"), {pkg}, [this, pkg](const QDBusMessage &r) {
        const QString job = ok(r) ? first(r).toString() : QString();
        if (!job.isEmpty() && m_uninstalling.contains(pkg)) {
            m_jobs.insert(job, pkg);
            return;
        }
        if (job.isEmpty() && m_uninstalling.remove(pkg))
            Q_EMIT failed(pkg, QStringLiteral("uninstall"),
                          r.errorMessage().isEmpty() ? tr("Android refused") : r.errorMessage());
    });
}

void AndroidApps::loadSpecialAccess(const QString &kind) {
    call(kDeckard, QStringLiteral("GetSpecialAccess"), {kind}, [this, kind](const QDBusMessage &r) {
        if (!ok(r)) {
            Q_EMIT failed(QString(), QStringLiteral("loadSpecialAccess"), r.errorMessage());
            return;
        }
        QVariantList apps = first(r).toList();
        for (QVariant &a : apps) {
            QVariantMap app = a.toMap();
            const QString pkg = app.value(QStringLiteral("pkg")).toString();
            app.insert(QStringLiteral("icon"), m_icons.value(pkg));
            a = app;
        }
        Q_EMIT specialAccessLoaded(kind, apps);
    });
}

void AndroidApps::setSpecialAccess(const QString &kind, const QString &pkg, bool granted) {
    act(QStringLiteral("setSpecialAccess"), pkg, QStringLiteral("SetSpecialAccess"), {kind, pkg, granted});
}

void AndroidApps::loadGoogleServices() {
    call(kDeckard, QStringLiteral("GetGoogleServices"), {}, [this](const QDBusMessage &r) {
        m_google = ok(r) ? first(r).toMap() : QVariantMap();
        Q_EMIT googleServicesChanged();
    });
}

void AndroidApps::setGoogleServices(const QString &key, bool enabled) {
    call(kDeckard, QStringLiteral("SetGoogleServices"), {key, enabled}, [this](const QDBusMessage &r) {
        if (!ok(r))
            Q_EMIT failed(QString(), QStringLiteral("setGoogleServices"), r.errorMessage());
        loadGoogleServices();
    });
}

void AndroidApps::openGoogleServices(const QString &page) {
    act(QStringLiteral("openGoogleServices"), QString(), QStringLiteral("OpenGoogleServices"), {page});
}

void AndroidApps::onRuntimeChanged(const QVariantMap &runtime) {
    m_runtime = runtime;
    Q_EMIT runtimeChanged();
}

void AndroidApps::onAppChanged(const QString &pkg) {
    Q_EMIT appChanged(pkg);
}

// A removed app has no details left to load: its page closes instead.
void AndroidApps::onPackageChanged(const QString &pkg, const QString &change) {
    refresh();
    if (change == QLatin1String("removed"))
        Q_EMIT appRemoved(pkg);
    else
        Q_EMIT appChanged(pkg);
}

// Finished can come before the reply that names the job, so the package
// matches too.
void AndroidApps::onFinished(const QString &job, bool succeeded, const QString &finishedPkg, const QString &message) {
    QString pkg = m_jobs.take(job);
    if (pkg.isEmpty() && m_uninstalling.contains(finishedPkg))
        pkg = finishedPkg;
    if (pkg.isEmpty() || !m_uninstalling.remove(pkg))
        return;
    if (succeeded)
        Q_EMIT done(pkg, QStringLiteral("uninstall"));
    else
        Q_EMIT failed(pkg, QStringLiteral("uninstall"), message.isEmpty() ? tr("Android refused") : message);
    refresh();
}

void AndroidApps::onOwnerChanged(const QString &, const QString &, const QString &newOwner) {
    if (newOwner.isEmpty()) {
        setAvailable(false);
        m_apps.clear();
        Q_EMIT appsChanged();
    } else {
        refresh();
    }
}
