#include "cgroupmanager.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QTextStream>
#include <QThread>

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
        qCInfo(lcCgroup) << "cgroup v2 not mounted at /sys/fs/cgroup";
        return false;
    }

    const QString shellPath = readShellCgroupPath();
    if (shellPath.isEmpty()) {
        qCInfo(lcCgroup) << "couldn't read /proc/self/cgroup";
        return false;
    }

    // We want marathon-apps as a SIBLING of the shell's own scope, both
    // under the delegated marathon.slice. Putting it as a child of the
    // shell's scope hits two problems: the scope's ACL chown happens
    // asynchronously after systemd-run returns (transient EACCES at boot),
    // and the no-internal-processes rule blocks controller enablement
    // when the scope has both processes (the shell) and children.
    //
    // Find marathon.slice in the path: it's always the immediate parent
    // of the marathon-shell-*.scope component when launched via
    // marathon-shell-session's systemd-run wrapper.
    QString   parentPath = shellPath;
    const int scopeIdx   = parentPath.lastIndexOf(QStringLiteral("/marathon-shell-"));
    if (scopeIdx <= 0 || !parentPath.endsWith(QStringLiteral(".scope"))) {
        qCInfo(lcCgroup) << "shell not inside marathon-shell-*.scope (cgroup:" << shellPath
                         << ") — running unwrapped? freeze will be log-only";
        return false;
    }
    const QString slicePath = parentPath.left(scopeIdx); // .../marathon.slice
    const QString sliceAbs  = QStringLiteral("/sys/fs/cgroup") + slicePath;
    m_appsRoot              = sliceAbs + QStringLiteral("/marathon-apps");

    QDir parent(sliceAbs);
    if (!parent.exists()) {
        qCInfo(lcCgroup) << "marathon.slice cgroup dir missing:" << sliceAbs;
        return false;
    }

    // Retry mkdir with backoff: systemd's delegate-chown of marathon.slice
    // is async after the user manager creates the scope. We may hit EACCES
    // for a few hundred ms after boot. Five attempts at 150 ms apart cover
    // the typical lag without burning real time.
    bool made = false;
    for (int attempt = 0; attempt < 5; ++attempt) {
        if (parent.exists(QStringLiteral("marathon-apps")) ||
            parent.mkdir(QStringLiteral("marathon-apps"))) {
            made = true;
            break;
        }
        QThread::msleep(150);
    }
    if (!made) {
        qCInfo(lcCgroup) << "mkdir" << m_appsRoot << "failed after retries —"
                         << "marathon.slice not delegated to user? freeze will be log-only";
        return false;
    }

    // Enable the controllers we want children of marathon-apps to see.
    // Best-effort: cgroup.freeze itself is in the v2 core (not a
    // controller) so this isn't load-bearing.
    QFile subtree(m_appsRoot + QStringLiteral("/cgroup.subtree_control"));
    if (subtree.open(QIODevice::WriteOnly)) {
        subtree.write("+memory +pids");
        subtree.close();
    }
    return true;
}

QString CgroupManager::readShellCgroupPath() {
    // /proc/self/cgroup stats as size 0; QTextStream(QIODevice::Text) can
    // see 0 bytes and report eof immediately. Use readAll() on the raw
    // file, which the kernel populates inline.
    QFile f(QStringLiteral("/proc/self/cgroup"));
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QByteArray data = f.readAll();
    f.close();
    for (const QByteArray &line : data.split('\n')) {
        // cgroup v2 unified hierarchy: a single line starting "0::/...".
        if (line.startsWith("0::"))
            return QString::fromUtf8(line.mid(3)).trimmed();
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
            qCInfo(lcCgroup) << "mkdir" << appPath << "failed";
            return {};
        }
    } else {
        // An existing cgroup dir may be left over from a previous instance
        // of this app and could be in a Frozen state. Migrating the new
        // PID into a frozen cgroup would freeze the new process at birth
        // before AppLifecycleManager has a chance to set its state. Thaw
        // pre-emptively; AppLifecycleManager will re-freeze later if the
        // state machine asks for it.
        writeFile(appPath + QStringLiteral("/cgroup.freeze"), QByteArrayLiteral("0"));
    }
    if (!writeFile(appPath + QStringLiteral("/cgroup.procs"), QByteArray::number(pid))) {
        // PID may not be ours anymore (race with exit). Don't recursive-
        // remove though — there may be other PIDs of the same appId still
        // in the cgroup (e.g. background runner instance still running).
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
