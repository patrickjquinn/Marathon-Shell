#ifndef UPDATESERVICE_H
#define UPDATESERVICE_H

#include <QDateTime>
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
    // The screen is off and no call or alarm is ringing or active.
    bool idle = false;
};

// Over-the-air updates of the OS image for Settings. Checks the signed
// feed, gates downloads on an unmetered network and a charged battery, and
// reports a rollback when the booted image is older than one it installed.
// notice() fires once per version for each kind of news. With automatic
// updates (on by default) an update downloads once the gates allow, and an
// installed one restarts between 02:00 and 05:00 when the device is idle on
// charge; "Tonight" asks for that restart without them.
//
// Settings keys (group "updates"): autoCheck, autoUpdate, installedVersion,
// installedBootId, lastChecked, lastSeenVersion, notice/<kind>,
// tonightVersion.
class UpdateService : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString state READ stateName NOTIFY stateChanged)
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString osVersion READ osVersion CONSTANT)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY stateChanged)
    Q_PROPERTY(qint64 downloadSize READ downloadSize NOTIFY stateChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY stateChanged)
    Q_PROPERTY(QString currentReleaseNotes READ currentReleaseNotes NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY stateChanged)
    Q_PROPERTY(QString blockedReason READ blockedReason NOTIFY stateChanged)
    Q_PROPERTY(QString rolledBackVersion READ rolledBackVersion NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(qint64 lastCheckedMs READ lastCheckedMs NOTIFY stateChanged)
    Q_PROPERTY(bool autoUpdate READ autoUpdate WRITE setAutoUpdate NOTIFY stateChanged)
    Q_PROPERTY(bool restartScheduled READ restartScheduled NOTIFY stateChanged)

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

    // Available: version can be downloaded. Restart: version is installed
    // and waits for a restart. RolledBack: version failed to start.
    // Updated: this boot is the first into version.
    enum class Notice : quint8 {
        Available,
        Restart,
        RolledBack,
        Updated,
    };
    Q_ENUM(Notice)

    UpdateService(UpdateBackend *backend, std::function<UpdateConditions()> conditions,
                  const QString &osVersion, const QString &bootId, std::function<QDateTime()> clock,
                  QObject *parent = nullptr);

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
    QString currentReleaseNotes() const {
        return m_currentReleaseNotes;
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
    bool autoUpdate() const {
        return m_autoUpdate;
    }
    void setAutoUpdate(bool on);
    bool restartScheduled() const;
    // When the next overnight restart window opens; invalid if none is due.
    QDateTime nextRestartWindow() const {
        return m_nextRestartWindow;
    }

    Q_INVOKABLE void checkNow();
    Q_INVOKABLE void install();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void reboot();
    // "Tonight": restart overnight for the installed update.
    Q_INVOKABLE void scheduleRestart();

    // "metered", "battery" or "" when a download may start.
    static QString blockReason(const UpdateConditions &c);
    // IMAGE_VERSION from an os-release file.
    static QString imageVersion(const QString &osReleasePath);

  public slots:
    // Something an automatic download or an overnight restart waits for
    // may have changed: the network, the charger, the screen, a call.
    void reconsider();

  signals:
    void stateChanged();
    void rebootRequested();
    void notice(UpdateService::Notice kind, const QString &version);
    void restartWindowChanged();

  private:
    void           setState(State state);
    void           markChecked();
    void           announce(Notice kind, const QString &version);
    bool           autoInstall();
    void           armRestart();
    void           onProbed(bool supported, const QString &installedVersion);
    void           onChecked(const QString &version);
    void           onReleaseInfo(const QString &version, qint64 downloadSize, const QString &notes);
    void           onProgress(int percent);
    void           onInstalled(const QString &version);
    void           onFailed(const QString &error);

    UpdateBackend *m_backend;
    std::function<UpdateConditions()> m_conditions;
    std::function<QDateTime()>        m_clock;
    QTimer                           *m_autoCheckTimer;
    QTimer                           *m_restartTimer;

    State                             m_state = State::Probing;
    QString                           m_currentVersion;
    QString                           m_osVersion;
    QString                           m_bootId;
    QString                           m_availableVersion;
    qint64                            m_downloadSize = -1;
    QString                           m_releaseNotes;
    QString                           m_currentReleaseNotes;
    int                               m_progress = 0;
    QString                           m_blockedReason;
    QString                           m_rolledBackVersion;
    QString                           m_lastError;
    qint64                            m_lastCheckedMs = 0;
    bool                              m_autoUpdate    = true;
    QString                           m_tonightVersion;
    QString                           m_cancelledVersion;
    QDateTime                         m_nextRestartWindow;
};

#endif
