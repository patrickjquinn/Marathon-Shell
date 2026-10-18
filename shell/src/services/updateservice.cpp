#include "updateservice.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QFile>
#include <QMetaEnum>
#include <QSettings>

namespace {
    constexpr int    kFirstCheckDelayMs   = 30 * 1000;
    constexpr int    kAutoCheckIntervalMs = 6 * 60 * 60 * 1000;
    constexpr double kMinBatteryPercent   = 30.0;
    constexpr int    kRestartFromHour     = 2;
    constexpr int    kRestartUntilHour    = 5;

    bool             charging(const UpdateConditions &c) {
        return c.batteryState == 1 || c.batteryState == 4 || c.batteryState == 5;
    }
} // namespace

UpdateService::UpdateService(UpdateBackend *backend, std::function<UpdateConditions()> conditions,
                             const QString &osVersion, const QString &bootId,
                             std::function<QDateTime()> clock, QObject *parent)
    : QObject(parent)
    , m_backend(backend)
    , m_conditions(std::move(conditions))
    , m_clock(std::move(clock))
    , m_autoCheckTimer(new QTimer(this))
    , m_restartTimer(new QTimer(this))
    , m_currentVersion(QCoreApplication::applicationVersion())
    , m_osVersion(osVersion)
    , m_bootId(bootId) {
    QSettings s;
    m_lastCheckedMs  = s.value(QStringLiteral("updates/lastChecked")).toLongLong();
    m_autoUpdate     = s.value(QStringLiteral("updates/autoUpdate"), true).toBool();
    m_tonightVersion = s.value(QStringLiteral("updates/tonightVersion")).toString();
    m_backend->setParent(this);
    connect(m_backend, &UpdateBackend::probed, this, &UpdateService::onProbed);
    connect(m_backend, &UpdateBackend::checked, this, &UpdateService::onChecked);
    connect(m_backend, &UpdateBackend::releaseInfo, this, &UpdateService::onReleaseInfo);
    connect(m_backend, &UpdateBackend::progress, this, &UpdateService::onProgress);
    connect(m_backend, &UpdateBackend::installing, this, &UpdateService::onInstalling);
    connect(m_backend, &UpdateBackend::installed, this, &UpdateService::onInstalled);
    connect(m_backend, &UpdateBackend::failed, this, &UpdateService::onFailed);

    m_autoCheckTimer->setInterval(kAutoCheckIntervalMs);
    connect(m_autoCheckTimer, &QTimer::timeout, this, &UpdateService::checkNow);
    m_restartTimer->setSingleShot(true);
    connect(m_restartTimer, &QTimer::timeout, this, &UpdateService::armRestart);

    m_backend->probe();
}

QString UpdateService::stateName() const {
    QString name = QString::fromLatin1(QMetaEnum::fromType<State>().valueToKey(int(m_state)));
    name[0]      = name[0].toLower();
    return name;
}

void UpdateService::setState(State state) {
    m_state = state;
    emit stateChanged();
    armRestart();
}

void UpdateService::onProbed(bool supported, const QString &installedVersion) {
    if (!supported || m_osVersion.isEmpty()) {
        setState(State::Unsupported);
        return;
    }

    QSettings s;
    s.beginGroup(QStringLiteral("updates"));
    const bool    autoCheck = s.value(QStringLiteral("autoCheck"), true).toBool();
    const QString ours      = s.value(QStringLiteral("installedVersion")).toString();
    // Before lastSeenVersion was kept, only an install of ours says this
    // version is new.
    const QString seen    = s.value(QStringLiteral("lastSeenVersion")).toString();
    const bool    updated = seen.isEmpty() ? ours == m_osVersion : seen != m_osVersion;
    s.setValue(QStringLiteral("lastSeenVersion"), m_osVersion);
    // An image installed in an earlier boot that is not the one running
    // failed its health check: systemd-boot fell back to this one.
    if (!installedVersion.isEmpty() && installedVersion != m_osVersion) {
        if (ours == installedVersion &&
            s.value(QStringLiteral("installedBootId")).toString() != m_bootId) {
            m_rolledBackVersion = installedVersion;
            setState(State::RolledBack);
            announce(Notice::RolledBack, installedVersion);
        } else {
            m_availableVersion = installedVersion;
            setState(State::ReadyToReboot);
            announce(Notice::Restart, installedVersion);
            return;
        }
    } else {
        setState(State::Idle);
        if (updated) {
            announce(Notice::Updated, m_osVersion);
            m_backend->fetchReleaseInfo(m_osVersion);
        }
    }

    if (autoCheck) {
        QTimer::singleShot(kFirstCheckDelayMs, this, &UpdateService::checkNow);
        m_autoCheckTimer->start();
    }
}

void UpdateService::announce(Notice kind, const QString &version) {
    QSettings     s;
    const QString key = QStringLiteral("updates/notice/") +
        QString::fromLatin1(QMetaEnum::fromType<Notice>().valueToKey(int(kind)));
    if (s.value(key).toString() == version)
        return;
    s.setValue(key, version);
    emit notice(kind, version);
}

void UpdateService::markChecked() {
    m_lastCheckedMs = QDateTime::currentMSecsSinceEpoch();
    QSettings().setValue(QStringLiteral("updates/lastChecked"), m_lastCheckedMs);
}

void UpdateService::checkNow() {
    switch (m_state) {
        case State::Idle:
        case State::UpToDate:
        case State::Available:
        case State::RolledBack:
        case State::Error: break;
        default: return;
    }
    m_lastError.clear();
    m_blockedReason.clear();
    setState(State::Checking);
    m_backend->checkNew();
}

void UpdateService::onChecked(const QString &version) {
    if (m_state != State::Checking)
        return;
    markChecked();
    if (m_currentReleaseNotes.isEmpty())
        m_backend->fetchReleaseInfo(m_osVersion);
    if (version.isEmpty()) {
        m_availableVersion.clear();
        setState(m_rolledBackVersion.isEmpty() ? State::UpToDate : State::RolledBack);
        return;
    }
    if (version != m_availableVersion) {
        m_availableVersion = version;
        m_downloadSize     = -1;
        m_releaseNotes.clear();
    }
    setState(State::Available);
    m_backend->fetchReleaseInfo(version);
    if (!autoInstall())
        announce(Notice::Available, version);
}

void UpdateService::onReleaseInfo(const QString &version, qint64 downloadSize,
                                  const QString &notes) {
    if (version == m_osVersion && !notes.isEmpty()) {
        m_currentReleaseNotes = notes;
        emit stateChanged();
    }
    if (version != m_availableVersion)
        return;
    m_downloadSize = downloadSize;
    m_releaseNotes = notes;
    emit stateChanged();
}

QString UpdateService::blockReason(const UpdateConditions &c) {
    if (c.metered == 1 || c.metered == 3)
        return QStringLiteral("metered");
    if (c.batteryPresent && !charging(c) && c.batteryPercent < kMinBatteryPercent)
        return QStringLiteral("battery");
    return {};
}

void UpdateService::install() {
    if (m_state != State::Available)
        return;
    m_blockedReason = blockReason(m_conditions());
    if (!m_blockedReason.isEmpty()) {
        emit stateChanged();
        return;
    }
    m_lastError.clear();
    m_progress   = 0;
    m_installing = false;
    setState(State::Downloading);
    m_backend->install();
}

void UpdateService::cancel() {
    if (m_state != State::Downloading)
        return;
    m_backend->cancel();
    m_cancelledVersion = m_availableVersion;
    m_progress         = 0;
    setState(State::Available);
}

void UpdateService::onProgress(int percent) {
    if (m_state != State::Downloading || percent == m_progress)
        return;
    m_progress = percent;
    emit stateChanged();
}

void UpdateService::onInstalling() {
    if (m_state != State::Downloading)
        return;
    m_installing = true;
    m_progress   = 0;
    emit stateChanged();
}

void UpdateService::onInstalled(const QString &version) {
    if (m_state != State::Downloading)
        return;
    QSettings s;
    s.beginGroup(QStringLiteral("updates"));
    s.setValue(QStringLiteral("installedVersion"), version);
    s.setValue(QStringLiteral("installedBootId"), m_bootId);
    s.endGroup();
    s.sync();
    m_availableVersion = version;
    m_progress         = 100;
    m_autoCheckTimer->stop();
    setState(State::ReadyToReboot);
    announce(Notice::Restart, version);
}

void UpdateService::onFailed(const QString &error) {
    if (m_state != State::Checking && m_state != State::Downloading)
        return;
    qWarning() << "[UpdateService]" << stateName() << "failed:" << error;
    if (m_state == State::Checking)
        markChecked();
    m_lastError = error;
    setState(State::Error);
}

void UpdateService::reboot() {
    if (m_state == State::ReadyToReboot)
        emit rebootRequested();
}

void UpdateService::setAutoUpdate(bool on) {
    if (on == m_autoUpdate)
        return;
    m_autoUpdate = on;
    QSettings().setValue(QStringLiteral("updates/autoUpdate"), on);
    emit stateChanged();
    reconsider();
}

bool UpdateService::autoInstall() {
    if (!m_autoUpdate || m_state != State::Available || m_availableVersion == m_cancelledVersion)
        return false;
    install();
    return m_state == State::Downloading;
}

bool UpdateService::restartScheduled() const {
    return m_state == State::ReadyToReboot &&
        (m_autoUpdate || m_tonightVersion == m_availableVersion);
}

void UpdateService::scheduleRestart() {
    if (m_state != State::ReadyToReboot)
        return;
    m_tonightVersion = m_availableVersion;
    QSettings().setValue(QStringLiteral("updates/tonightVersion"), m_tonightVersion);
    emit stateChanged();
    armRestart();
}

void UpdateService::reconsider() {
    autoInstall();
    armRestart();
}

// Restarts now if this is the window and the device is idle on charge, and
// sets the timer for the next window.
void UpdateService::armRestart() {
    QDateTime next;
    if (restartScheduled()) {
        const QDateTime now  = m_clock();
        const int       hour = now.time().hour();
        if (hour >= kRestartFromHour && hour < kRestartUntilHour) {
            const UpdateConditions c = m_conditions();
            if (c.idle && (!c.batteryPresent || charging(c))) {
                qInfo() << "[UpdateService] restarting overnight into" << m_availableVersion;
                emit rebootRequested();
            }
        }
        next = QDateTime(now.date(), QTime(kRestartFromHour, 0));
        if (now >= next)
            next = next.addDays(1);
        m_restartTimer->start(int(now.msecsTo(next)));
    } else {
        m_restartTimer->stop();
    }
    if (next != m_nextRestartWindow) {
        m_nextRestartWindow = next;
        emit restartWindowChanged();
    }
}

QString UpdateService::imageVersion(const QString &osReleasePath) {
    QFile f(osReleasePath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    while (!f.atEnd()) {
        const QString line = QString::fromUtf8(f.readLine()).trimmed();
        if (!line.startsWith(QLatin1String("IMAGE_VERSION=")))
            continue;
        QString value = line.mid(int(sizeof("IMAGE_VERSION=")) - 1);
        if (value.size() >= 2 && (value.startsWith('"') || value.startsWith('\'')) &&
            value.endsWith(value.front()))
            value = value.mid(1, value.size() - 2);
        return value;
    }
    return {};
}
