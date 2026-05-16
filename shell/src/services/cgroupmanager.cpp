#include "cgroupmanager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QTextStream>

Q_LOGGING_CATEGORY(lcCgroup, "marathon.lifecycle.cgroup")

CgroupManager::CgroupManager(QObject *parent)
    : QObject(parent) {
    m_available = initRootPath();
    if (m_available) {
        qCInfo(lcCgroup) << "available, apps root:" << m_appsRoot;
    } else {
        qCInfo(lcCgroup)
            << "cgroup v2 freezing unavailable; lifecycle freeze transitions will be logged only";
    }
}

bool CgroupManager::initRootPath() {
    // cgroup v2 mounts a single hierarchy at /sys/fs/cgroup. v1 has
    // controllers split across subdirs (/sys/fs/cgroup/freezer/...). We
    // explicitly require v2 here because v2's cgroup.freeze is the only
    // API that does what we need (full process pause; v1's freezer is
    // legacy + deprecated).
    QFile typeProbe(QStringLiteral("/sys/fs/cgroup/cgroup.controllers"));
    if (!typeProbe.exists()) {
        qCDebug(lcCgroup) << "cgroup v2 not mounted at /sys/fs/cgroup";
        return false;
    }

    const QString shellPath = readShellCgroupPath();
    if (shellPath.isEmpty()) {
        qCDebug(lcCgroup) << "couldn't read /proc/self/cgroup";
        return false;
    }

    const QString shellAbs = QStringLiteral("/sys/fs/cgroup") + shellPath;
    m_appsRoot             = shellAbs + QStringLiteral("/marathon-apps");

    QDir parent(shellAbs);
    if (!parent.exists()) {
        qCDebug(lcCgroup) << "shell cgroup dir missing:" << shellAbs;
        return false;
    }
    if (!parent.mkpath(QStringLiteral("marathon-apps"))) {
        qCDebug(lcCgroup) << "couldn't create marathon-apps under" << shellAbs
                          << "(no Delegate=yes on shell unit?)";
        return false;
    }
    // Enable the controllers we want children of marathon-apps to see.
    // This must be writable; if not, freeze still works (it's part of the
    // core cgroup v2 API, not a separately-enabled controller) but memory
    // accounting won't. Failure here is non-fatal.
    QFile subtree(m_appsRoot + QStringLiteral("/cgroup.subtree_control"));
    if (subtree.open(QIODevice::WriteOnly)) {
        subtree.write("+memory +cpu");
        subtree.close();
    }
    return true;
}

QString CgroupManager::readShellCgroupPath() {
    QFile f(QStringLiteral("/proc/self/cgroup"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    QTextStream in(&f);
    while (!in.atEnd()) {
        const QString line = in.readLine();
        // Format on cgroup v2: "0::/user.slice/user-1000.slice/..."
        if (line.startsWith(QStringLiteral("0::"))) {
            return line.mid(3);
        }
    }
    return {};
}

bool CgroupManager::writeFile(const QString &path, const QByteArray &data) const {
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCDebug(lcCgroup) << "open" << path << "failed:" << f.errorString();
        return false;
    }
    const qint64 n = f.write(data);
    f.close();
    if (n < 0) {
        qCDebug(lcCgroup) << "write" << path << "failed:" << f.errorString();
        return false;
    }
    return true;
}

QString CgroupManager::placeAppPid(qint64 pid, const QString &appId) {
    if (!m_available || pid <= 0 || appId.isEmpty())
        return {};
    const QString appPath = m_appsRoot + QStringLiteral("/marathon-app-") + appId;
    QDir          appsRoot(m_appsRoot);
    if (!appsRoot.exists(QStringLiteral("marathon-app-") + appId)) {
        if (!appsRoot.mkdir(QStringLiteral("marathon-app-") + appId)) {
            qCDebug(lcCgroup) << "mkdir" << appPath << "failed";
            return {};
        }
    }
    if (!writeFile(appPath + QStringLiteral("/cgroup.procs"), QByteArray::number(pid))) {
        // PID may not be ours anymore (race with exit). Tear down so we
        // don't leak empty cgroup dirs.
        QDir(appPath).removeRecursively();
        return {};
    }
    m_appPaths.insert(appId, appPath);
    qCInfo(lcCgroup) << "placed pid" << pid << "for" << appId << "into" << appPath;
    return appPath;
}

bool CgroupManager::setFrozen(const QString &cgroupPath, bool frozen) {
    if (!m_available || cgroupPath.isEmpty())
        return false;
    const QByteArray val = frozen ? QByteArrayLiteral("1") : QByteArrayLiteral("0");
    return writeFile(cgroupPath + QStringLiteral("/cgroup.freeze"), val);
}

bool CgroupManager::setAppFrozen(const QString &appId, bool frozen) {
    const QString path = m_appPaths.value(appId);
    if (path.isEmpty())
        return false;
    const bool ok = setFrozen(path, frozen);
    if (ok)
        qCInfo(lcCgroup) << (frozen ? "froze" : "thawed") << appId;
    return ok;
}

void CgroupManager::removeAppCgroup(const QString &appId) {
    const QString path = m_appPaths.take(appId);
    if (path.isEmpty())
        return;
    // cgroup directories with PIDs still in them can't be removed; that's
    // fine — the kernel cleans them when the last PID exits, and we'll
    // retry on the next launch (mkdir tolerates "already exists" via
    // mkdir+exists check above).
    QDir(path).removeRecursively();
}
