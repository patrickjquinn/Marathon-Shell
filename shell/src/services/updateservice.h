#ifndef UPDATESERVICE_H
#define UPDATESERVICE_H

#include <QObject>
#include <QString>
#include <QTimer>

#include <functional>

// The OS image's update mechanism, as UpdateService sees it. The device
// implementation is SysupdateBackend (systemd-sysupdated); tests use a fake.
class UpdateBackend : public QObject {
    Q_OBJECT

  public:
    using QObject::QObject;

    // probed(): whether the host has an update target, and the newest
    // version installed on disk (which differs from the booted one while an
    // update waits for a reboot, or after a rollback).
    virtual void probe() = 0;
    // checked(): the newer version on the server, or "".
    virtual void checkNew() = 0;
    // releaseInfo(): download size (-1 unknown) and notes for a version.
    virtual void fetchReleaseInfo(const QString &version) = 0;
    // progress() while downloading, then installed() or failed().
    virtual void install() = 0;
    virtual void cancel()  = 0;

  signals:
    void probed(bool supported, const QString &installedVersion);
    void checked(const QString &version);
    void releaseInfo(const QString &version, qint64 downloadSize, const QString &notes);
    void progress(int percent);
    void installed(const QString &version);
    void failed(const QString &error);
};

// What the system says about downloading right now.
struct UpdateConditions {
    // NetworkManager's NMMetered: 1 yes, 3 guess-yes.
    uint   metered        = 0;
    bool   batteryPresent = false;
    double batteryPercent = 0;
    // UPower device state: 1 charging, 4 fully charged, 5 pending charge.
    uint batteryState = 0;
};

// Over-the-air updates of the OS image for Settings. Checks the signed
// feed, gates downloads on an unmetered network and a charged battery, and
// reports a rollback when the booted image is older than one it installed.
//
// Settings keys (group "updates"): autoCheck, installedVersion,
// installedBootId.
class UpdateService : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString state READ stateName NOTIFY stateChanged)
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString osVersion READ osVersion CONSTANT)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY stateChanged)
    Q_PROPERTY(qint64 downloadSize READ downloadSize NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(QString blockedReason READ blockedReason NOTIFY stateChanged)
    Q_PROPERTY(QString rolledBackVersion READ rolledBackVersion NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(qint64 lastCheckedMs READ lastCheckedMs NOTIFY stateChanged)

  public:
    enum class State : quint8 {
        Probing,
        Unsupported,
        Idle,
        Checking,
        UpToDate,
        Available,
        Downloading,
        ReadyToReboot,
        RolledBack,
        Error,
    };
    Q_ENUM(State)

    UpdateService(UpdateBackend *backend, std::function<UpdateConditions()> conditions,
                  const QString &osVersion, const QString &bootId, QObject *parent = nullptr);

    State state() const {
        return m_state;
    }
    QString stateName() const;
    QString currentVersion() const {
        return m_currentVersion;
    }
    QString osVersion() const {
        return m_osVersion;
    }
    QString availableVersion() const {
        return m_availableVersion;
    }
    qint64 downloadSize() const {
        return m_downloadSize;
    }
    QString releaseNotes() const {
        return m_releaseNotes;
    }
    int progress() const {
        return m_progress;
    }
    QString blockedReason() const {
        return m_blockedReason;
    }
    QString rolledBackVersion() const {
        return m_rolledBackVersion;
    }
    QString lastError() const {
        return m_lastError;
    }
    qint64 lastCheckedMs() const {
        return m_lastCheckedMs;
    }

    Q_INVOKABLE void checkNow();
    Q_INVOKABLE void install();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void reboot();

    // "metered", "battery" or "" when a download may start.
    static QString blockReason(const UpdateConditions &c);
    // IMAGE_VERSION from an os-release file.
    static QString imageVersion(const QString &osReleasePath);

  signals:
    void stateChanged();
    void rebootRequested();

  private:
    void           setState(State state);
    void           onProbed(bool supported, const QString &installedVersion);
    void           onChecked(const QString &version);
    void           onReleaseInfo(const QString &version, qint64 downloadSize, const QString &notes);
    void           onProgress(int percent);
    void           onInstalled(const QString &version);
    void           onFailed(const QString &error);

    UpdateBackend *m_backend;
    std::function<UpdateConditions()> m_conditions;
    QTimer                           *m_autoCheckTimer;

    State                             m_state = State::Probing;
    QString                           m_currentVersion;
    QString                           m_osVersion;
    QString                           m_bootId;
    QString                           m_availableVersion;
    qint64                            m_downloadSize = -1;
    QString                           m_releaseNotes;
    int                               m_progress = 0;
    QString                           m_blockedReason;
    QString                           m_rolledBackVersion;
    QString                           m_lastError;
    qint64                            m_lastCheckedMs = 0;
};

#endif
