#include "backgroundtaskobserver.h"

#include "applaunchservice.h"
#include "applifecyclemanager.h"
#include "managers/mpris2controller.h"
#include "telephonyservice.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QLoggingCategory>

Q_LOGGING_CATEGORY(lcBgObs, "marathon.lifecycle.observer")

// Telephony states that count as "phone is in use". Anything outside this
// set (idle, ended, empty) drops the active-call capability.
static bool callIsActive(const QString &state) {
    if (state.isEmpty())
        return false;
    const QString s = state.toLower();
    return s == "active" || s == "ringing" || s == "incoming" || s == "dialing" ||
        s == "outgoing" || s == "alerting" || s == "held" || s == "waiting";
}

BackgroundTaskObserver::BackgroundTaskObserver(AppLifecycleManager *lifecycle,
                                               AppLaunchService *launch, MPRIS2Controller *mpris,
                                               TelephonyService *telephony, QObject *parent)
    : QObject(parent)
    , m_lifecycle(lifecycle)
    , m_launch(launch)
    , m_mpris(mpris)
    , m_telephony(telephony) {
    if (m_mpris) {
        connect(m_mpris, &MPRIS2Controller::playbackStatusChanged, this,
                &BackgroundTaskObserver::onMprisPlaybackChanged);
        connect(m_mpris, &MPRIS2Controller::activePlayerChanged, this,
                &BackgroundTaskObserver::onMprisActivePlayerChanged);
    }
    if (m_telephony) {
        connect(m_telephony, &TelephonyService::callStateChanged, this,
                &BackgroundTaskObserver::onCallStateChanged);
    }
}

void BackgroundTaskObserver::onMprisPlaybackChanged() {
    if (!m_mpris || !m_lifecycle)
        return;
    if (m_mpris->isPlaying()) {
        const QString busName = m_mpris->currentBusName();
        const QString appId   = resolveAppIdForBusName(busName);
        if (appId.isEmpty()) {
            qCDebug(lcBgObs) << "playback active but no Marathon appId for bus" << busName;
            releaseAudioPlayback();
            return;
        }
        claimAudioPlaybackFor(appId);
    } else {
        // Paused/stopped/empty all release the capability — the freeze
        // debounce then decides whether the app is still warm enough
        // to deserve foreground-quality oom_score.
        releaseAudioPlayback();
    }
}

void BackgroundTaskObserver::onMprisActivePlayerChanged() {
    if (!m_mpris)
        return;
    // Player switched. If the new one is already playing, re-resolve
    // (which will also release whatever the previous holder was).
    onMprisPlaybackChanged();
}

void BackgroundTaskObserver::claimAudioPlaybackFor(const QString &appId) {
    if (!m_lifecycle || appId.isEmpty())
        return;
    if (m_audioPlaybackAppId == appId)
        return;
    if (!m_audioPlaybackAppId.isEmpty() && m_audioPlaybackAppId != appId) {
        m_lifecycle->removeCapability(m_audioPlaybackAppId, "audio-playback");
    }
    m_lifecycle->addCapability(appId, "audio-playback");
    m_audioPlaybackAppId = appId;
}

void BackgroundTaskObserver::releaseAudioPlayback() {
    if (!m_lifecycle || m_audioPlaybackAppId.isEmpty())
        return;
    m_lifecycle->removeCapability(m_audioPlaybackAppId, "audio-playback");
    m_audioPlaybackAppId.clear();
}

void BackgroundTaskObserver::onCallStateChanged(const QString &state) {
    if (!m_lifecycle)
        return;
    // Hard-wire to "phone" — TelephonyService doesn't yet attribute calls
    // to a specific publisher. A future VoIP integration that wants to
    // hold the active-call cap will go through BeginBackgroundTask (Phase
    // B), bypassing this observer.
    const QString appId = QStringLiteral("phone");
    if (callIsActive(state)) {
        if (m_activeCallAppId != appId) {
            if (!m_activeCallAppId.isEmpty())
                m_lifecycle->removeCapability(m_activeCallAppId, "active-call");
            m_lifecycle->addCapability(appId, "active-call");
            m_activeCallAppId = appId;
        }
    } else if (!m_activeCallAppId.isEmpty()) {
        m_lifecycle->removeCapability(m_activeCallAppId, "active-call");
        m_activeCallAppId.clear();
    }
}

QString BackgroundTaskObserver::resolveAppIdForBusName(const QString &busName) const {
    if (busName.isEmpty() || !m_launch)
        return {};
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return {};
    QDBusInterface   dbus("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                          bus);
    QDBusReply<uint> reply = dbus.call("GetConnectionUnixProcessID", busName);
    if (!reply.isValid()) {
        qCDebug(lcBgObs) << "GetConnectionUnixProcessID failed for" << busName << ":"
                         << reply.error().message();
        return {};
    }
    const qint64  pid   = static_cast<qint64>(reply.value());
    const QString appId = m_launch->appIdForPid(pid);
    qCDebug(lcBgObs) << "bus" << busName << "→ pid" << pid << "→ appId" << appId;
    return appId;
}
