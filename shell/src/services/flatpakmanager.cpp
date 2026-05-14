#include "flatpakmanager.h"

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QTextStream>

namespace {
    constexpr int kFlatpakTimeoutMs = 4000;

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

bool FlatpakManager::runFlatpak(const QStringList &args, QByteArray *stdOut) const {
    if (!m_available)
        return false;

    QProcess proc;
    proc.start(flatpakBinary(), args);
    if (!proc.waitForFinished(kFlatpakTimeoutMs)) {
        qWarning() << "[FlatpakManager] timed out:" << args;
        proc.kill();
        return false;
    }
    if (stdOut)
        *stdOut = proc.readAllStandardOutput();
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        qWarning() << "[FlatpakManager]" << args << "failed exit=" << proc.exitCode()
                   << proc.readAllStandardError();
        return false;
    }
    return true;
}

QVariantList FlatpakManager::installedApps() {
    if (m_installedCached)
        return m_installedCache;

    QByteArray out;
    if (!runFlatpak({QStringLiteral("list"), QStringLiteral("--app"),
                     QStringLiteral("--columns=application,branch,arch,installation")},
                    &out)) {
        m_installedCache.clear();
        m_installedCached = true;
        return m_installedCache;
    }

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

    m_installedCache  = apps;
    m_installedCached = true;
    return m_installedCache;
}

QVariantMap FlatpakManager::permissions(const QString &ref) {
    if (ref.isEmpty())
        return {};
    QByteArray out;
    if (!runFlatpak({QStringLiteral("info"), QStringLiteral("--show-permissions"), ref}, &out))
        return {};
    return parsePermissionsIni(QString::fromUtf8(out));
}

QVariantMap FlatpakManager::userOverrides(const QString &ref) {
    if (ref.isEmpty())
        return {};
    const QString path = overridesFilePath(ref);
    QFile         f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    const QString text = QString::fromUtf8(f.readAll());
    f.close();
    return parsePermissionsIni(text);
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

bool FlatpakManager::setTalkPolicy(const QString &ref, const QString &busName,
                                   const QString &policy) {
    if (ref.isEmpty() || busName.isEmpty())
        return false;

    QStringList args = {QStringLiteral("override"), QStringLiteral("--user")};
    if (policy == QLatin1String("allow") || policy == QLatin1String("talk"))
        args << QStringLiteral("--talk-name=") + busName;
    else if (policy == QLatin1String("own"))
        args << QStringLiteral("--own-name=") + busName;
    else if (policy == QLatin1String("none") || policy.isEmpty())
        args << QStringLiteral("--no-talk-name=") + busName;
    else {
        qWarning() << "[FlatpakManager] unknown talk policy:" << policy;
        return false;
    }
    args << ref;

    if (!runFlatpak(args))
        return false;
    emit overridesChanged(ref);
    return true;
}

bool FlatpakManager::setFilesystemPolicy(const QString &ref, const QString &path,
                                         const QString &mode) {
    if (ref.isEmpty() || path.isEmpty())
        return false;

    QStringList args = {QStringLiteral("override"), QStringLiteral("--user")};

    QString     suffix = path;
    if (mode == QLatin1String("ro") || mode == QLatin1String("rw") ||
        mode == QLatin1String("create"))
        suffix += QLatin1Char(':') + mode;
    else if (!mode.isEmpty()) {
        qWarning() << "[FlatpakManager] unknown filesystem mode:" << mode;
        return false;
    }

    if (mode.isEmpty())
        args << QStringLiteral("--nofilesystem=") + path;
    else
        args << QStringLiteral("--filesystem=") + suffix;

    args << ref;

    if (!runFlatpak(args))
        return false;
    emit overridesChanged(ref);
    return true;
}

bool FlatpakManager::resetOverrides(const QString &ref) {
    if (ref.isEmpty())
        return false;
    if (!runFlatpak(
            {QStringLiteral("override"), QStringLiteral("--user"), QStringLiteral("--reset"), ref}))
        return false;
    emit overridesChanged(ref);
    return true;
}

void FlatpakManager::refresh() {
    m_installedCached = false;
    m_installedCache.clear();
    emit installedAppsChanged();
}
