#include "flatpakmanager.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

namespace {
    constexpr int kFlatpakTimeoutMs = 8000;

    QString       flatpakBinary() {
        return QStringLiteral("flatpak");
    }

    QString overridesFilePath(const QString &ref) {
        const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
        return home + QStringLiteral("/.local/share/flatpak/overrides/") + ref;
    }
} // namespace

FlatpakManager::FlatpakManager(QObject *parent)
    : QObject(parent)
    , m_available(!QStandardPaths::findExecutable(flatpakBinary()).isEmpty()) {
    if (!m_available)
        qInfo() << "[FlatpakManager] flatpak binary not found; manager will return empty results";
}

void FlatpakManager::beginOp() {
    if (m_pendingOps++ == 0)
        emit loadingChanged();
}

void FlatpakManager::endOp() {
    if (--m_pendingOps == 0)
        emit loadingChanged();
}

void FlatpakManager::startProcess(const QStringList                                   &args,
                                  const std::function<void(bool, const QByteArray &)> &done) {
    if (!m_available) {
        done(false, {});
        return;
    }

    auto *proc = new QProcess(this);
    beginOp();

    auto *watchdog = new QTimer(proc);
    watchdog->setSingleShot(true);
    watchdog->setInterval(kFlatpakTimeoutMs);
    connect(watchdog, &QTimer::timeout, proc, [proc, args]() {
        qWarning() << "[FlatpakManager] timeout, killing:" << args;
        proc->kill();
    });

    connect(proc, &QProcess::finished, this,
            [this, proc, args, done](int code, QProcess::ExitStatus status) {
                endOp();
                const bool ok = (status == QProcess::NormalExit && code == 0);
                if (!ok)
                    qWarning() << "[FlatpakManager]" << args << "failed exit=" << code
                               << proc->readAllStandardError();
                done(ok, proc->readAllStandardOutput());
                proc->deleteLater();
            });

    connect(proc, &QProcess::errorOccurred, this, [proc, args](QProcess::ProcessError err) {
        qWarning() << "[FlatpakManager] error" << err << "on" << args;
    });

    proc->start(flatpakBinary(), args);
    watchdog->start();
}

void FlatpakManager::refresh() {
    startProcess({QStringLiteral("list"), QStringLiteral("--app"),
                  QStringLiteral("--columns=application,branch,arch,installation")},
                 [this](bool ok, const QByteArray &out) {
                     if (!ok)
                         return;
                     parseInstalled(out);
                     emit installedAppsChanged();
                 });
}

void FlatpakManager::parseInstalled(const QByteArray &out) {
    QVariantList apps;
    const auto   lines = QString::fromUtf8(out).split('\n', Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        const QStringList cols = line.split('\t');
        if (cols.size() < 4)
            continue;
        QVariantMap entry;
        entry.insert(QStringLiteral("ref"), cols.at(0));
        entry.insert(QStringLiteral("branch"), cols.at(1));
        entry.insert(QStringLiteral("arch"), cols.at(2));
        entry.insert(QStringLiteral("installation"), cols.at(3));
        apps.append(entry);
    }
    m_installed = apps;
}

void FlatpakManager::requestPermissions(const QString &ref) {
    if (ref.isEmpty())
        return;

    const auto cached = m_permCache.constFind(ref);
    if (cached != m_permCache.constEnd()) {
        const QVariantMap &copy = cached.value();
        QMetaObject::invokeMethod(
            this, [this, ref, copy]() { emit permissionsReady(ref, copy); }, Qt::QueuedConnection);
        return;
    }

    startProcess({QStringLiteral("info"), QStringLiteral("--show-permissions"), ref},
                 [this, ref](bool ok, const QByteArray &out) {
                     if (!ok) {
                         emit permissionsReady(ref, {});
                         return;
                     }
                     const QVariantMap perms = parsePermissionsIni(QString::fromUtf8(out));
                     m_permCache.insert(ref, perms);
                     emit permissionsReady(ref, perms);
                 });
}

void FlatpakManager::requestUserOverrides(const QString &ref) {
    if (ref.isEmpty())
        return;

    QMetaObject::invokeMethod(
        this,
        [this, ref]() {
            const QString path = overridesFilePath(ref);
            QFile         f(path);
            if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
                emit userOverridesReady(ref, {});
                return;
            }
            const QString text = QString::fromUtf8(f.readAll());
            f.close();
            emit userOverridesReady(ref, parsePermissionsIni(text));
        },
        Qt::QueuedConnection);
}

QVariantMap FlatpakManager::cachedPermissions(const QString &ref) const {
    return m_permCache.value(ref);
}

QVariantMap FlatpakManager::parsePermissionsIni(const QString &iniText) const {
    QVariantMap result;
    QString     currentSection;
    QVariantMap currentBody;

    auto        flush = [&]() {
        if (!currentSection.isEmpty() && !currentBody.isEmpty())
            result.insert(currentSection, currentBody);
    };

    const auto lines = iniText.split('\n');
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        if (line.startsWith('[') && line.endsWith(']')) {
            flush();
            currentSection = line.mid(1, line.size() - 2);
            currentBody    = QVariantMap();
            continue;
        }
        const int eq = line.indexOf('=');
        if (eq < 0)
            continue;
        const QString key   = line.left(eq).trimmed();
        const QString value = line.mid(eq + 1).trimmed();
        currentBody.insert(key, value);
    }
    flush();
    return result;
}

void FlatpakManager::setTalkPolicy(const QString &ref, const QString &busName,
                                   const QString &policy) {
    if (ref.isEmpty() || busName.isEmpty()) {
        emit overrideApplied(ref, false);
        return;
    }

    QStringList args = {QStringLiteral("override"), QStringLiteral("--user")};
    if (policy == QLatin1String("allow") || policy == QLatin1String("talk"))
        args << QStringLiteral("--talk-name=") + busName;
    else if (policy == QLatin1String("own"))
        args << QStringLiteral("--own-name=") + busName;
    else if (policy == QLatin1String("none") || policy.isEmpty())
        args << QStringLiteral("--no-talk-name=") + busName;
    else {
        qWarning() << "[FlatpakManager] unknown talk policy:" << policy;
        emit overrideApplied(ref, false);
        return;
    }
    args << ref;

    startProcess(args, [this, ref](bool ok, const QByteArray &) {
        if (ok)
            m_permCache.remove(ref);
        emit overrideApplied(ref, ok);
    });
}

void FlatpakManager::setFilesystemPolicy(const QString &ref, const QString &path,
                                         const QString &mode) {
    if (ref.isEmpty() || path.isEmpty()) {
        emit overrideApplied(ref, false);
        return;
    }

    QStringList args = {QStringLiteral("override"), QStringLiteral("--user")};

    if (mode.isEmpty()) {
        args << QStringLiteral("--nofilesystem=") + path;
    } else if (mode == QLatin1String("ro") || mode == QLatin1String("rw") ||
               mode == QLatin1String("create")) {
        args << QStringLiteral("--filesystem=") + path + QLatin1Char(':') + mode;
    } else {
        qWarning() << "[FlatpakManager] unknown filesystem mode:" << mode;
        emit overrideApplied(ref, false);
        return;
    }

    args << ref;

    startProcess(args, [this, ref](bool ok, const QByteArray &) {
        if (ok)
            m_permCache.remove(ref);
        emit overrideApplied(ref, ok);
    });
}

void FlatpakManager::resetOverrides(const QString &ref) {
    if (ref.isEmpty()) {
        emit overrideApplied(ref, false);
        return;
    }

    startProcess(
        {QStringLiteral("override"), QStringLiteral("--user"), QStringLiteral("--reset"), ref},
        [this, ref](bool ok, const QByteArray &) {
            if (ok)
                m_permCache.remove(ref);
            emit overrideApplied(ref, ok);
        });
}
