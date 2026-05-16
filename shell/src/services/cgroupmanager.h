#pragma once

#include <QHash>
#include <QObject>
#include <QString>

// Best-effort cgroup v2 placement and freeze/thaw for marathon-app-runner
// PIDs. The shell does not require cgroup delegation to operate; if the
// kernel/systemd setup doesn't give us write permission under our own
// cgroup, every operation becomes a logged no-op and the lifecycle state
// machine still runs (just without real freezing). On a duranium image the
// marathon-shell.service unit ships with `Delegate=yes` so the shell can
// subdivide its slice.
//
// Layout (under the shell's own cgroup):
//   <shell-cgroup>/
//     marathon-apps/
//       marathon-app-<appId>/
//         cgroup.procs        -- contains the runner PID
//         cgroup.freeze       -- 0 / 1
class CgroupManager : public QObject {
    Q_OBJECT

  public:
    explicit CgroupManager(QObject *parent = nullptr);

    bool isAvailable() const {
        return m_available;
    }
    QString rootPath() const {
        return m_appsRoot;
    }

    // Creates the per-app cgroup if needed and places PID inside. Returns
    // the absolute cgroup directory on success, empty on failure.
    QString placeAppPid(qint64 pid, const QString &appId);

    // Freeze or thaw an app by its cgroup path. Returns true if the write
    // succeeded; false if cgroup unavailable or write blocked.
    bool setFrozen(const QString &cgroupPath, bool frozen);

    // Convenience: lookup-then-freeze. Tracks per-appId cgroup paths from
    // prior placeAppPid calls.
    bool setAppFrozen(const QString &appId, bool frozen);

    // Tear down cgroup directory (rmdir) when app exits. Tolerant of the
    // dir not existing.
    void removeAppCgroup(const QString &appId);

  private:
    bool                    initRootPath();
    static QString          readShellCgroupPath();
    bool                    writeFile(const QString &path, const QByteArray &data) const;

    bool                    m_available = false;
    QString                 m_appsRoot;
    QHash<QString, QString> m_appPaths;
};
