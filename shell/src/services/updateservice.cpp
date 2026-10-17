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
} // namespace

UpdateService::UpdateService(UpdateBackend *backend, std::function<UpdateConditions()> conditions,
                             const QString &osVersion, const QString &bootId, QObject *parent)
    : QObject(parent)
    , m_backend(backend)
    , m_conditions(std::move(conditions))
    , m_autoCheckTimer(new QTimer(this))
    , m_currentVersion(QCoreApplication::applicationVersion())
    , m_osVersion(osVersion)
    , m_bootId(bootId)
    , m_lastCheckedMs(QSettings().value(QStringLiteral("updates/lastChecked")).toLongLong()) {
    m_backend->setParent(this);
    connect(m_backend, &UpdateBackend::probed, this, &UpdateService::onProbed);
    connect(m_backend, &UpdateBackend::checked, this, &UpdateService::onChecked);
    connect(m_backend, &UpdateBackend::releaseInfo, this, &UpdateService::onReleaseInfo);
    connect(m_backend, &UpdateBackend::progress, this, &UpdateService::onProgress);
    connect(m_backend, &UpdateBackend::installed, this, &UpdateService::onInstalled);
    connect(m_backend, &UpdateBackend::failed, this, &UpdateService::onFailed);

    m_autoCheckTimer->setInterval(kAutoCheckIntervalMs);
    connect(m_autoCheckTimer, &QTimer::timeout, this, &UpdateService::checkNow);

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
}

void UpdateService::onProbed(bool supported, const QString &installedVersion) {
    if (!supported || m_osVersion.isEmpty()) {
        setState(State::Unsupported);
        return;
    }

    QSettings s;
    s.beginGroup(QStringLiteral("updates"));
    const bool autoCheck = s.value(QStringLiteral("autoCheck"), true).toBool();
    // An image installed in an earlier boot that is not the one running
    // failed its health check: systemd-boot fell back to this one.
    if (!installedVersion.isEmpty() && installedVersion != m_osVersion) {
        const bool ours =
            s.value(QStringLiteral("installedVersion")).toString() == installedVersion;
        if (ours && s.value(QStringLiteral("installedBootId")).toString() != m_bootId) {
            m_rolledBackVersion = installedVersion;
            setState(State::RolledBack);
        } else {
            m_availableVersion = installedVersion;
            setState(State::ReadyToReboot);
            return;
        }
    } else {
        setState(State::Idle);
    }

    if (autoCheck) {
        QTimer::singleShot(kFirstCheckDelayMs, this, &UpdateService::checkNow);
        m_autoCheckTimer->start();
    }
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
}

void UpdateService::onReleaseInfo(const QString &version, qint64 downloadSize,
                                  const QString &notes) {
    if (version != m_availableVersion)
        return;
    m_downloadSize = downloadSize;
    m_releaseNotes = notes;
    emit stateChanged();
}

QString UpdateService::blockReason(const UpdateConditions &c) {
    if (c.metered == 1 || c.metered == 3)
        return QStringLiteral("metered");
    const bool charging = c.batteryState == 1 || c.batteryState == 4 || c.batteryState == 5;
    if (c.batteryPresent && !charging && c.batteryPercent < kMinBatteryPercent)
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
    m_progress = 0;
    setState(State::Downloading);
    m_backend->install();
}

void UpdateService::cancel() {
    if (m_state != State::Downloading)
        return;
    m_backend->cancel();
    m_progress = 0;
    setState(State::Available);
}

void UpdateService::onProgress(int percent) {
    if (m_state != State::Downloading || percent == m_progress)
        return;
    m_progress = percent;
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
