#include "applifecyclemanager.h"

#include "applaunchservice.h"
#include "cgroupmanager.h"
#include "taskmodel.h"

#include <QDateTime>
#include <QFile>
#include <QLoggingCategory>
#include <QMetaObject>
#include <QPointer>
#include <QTimer>
#include <QVariant>

#include <csignal>
#include <limits>
#include <sys/types.h>

Q_LOGGING_CATEGORY(lcLifecycle, "marathon.lifecycle")

AppLifecycleManager::AppLifecycleManager(TaskModel *taskModel, AppLaunchService *appLaunchService,
                                         QObject *parent)
    : QObject(parent)
    , m_taskModel(taskModel)
    , m_appLaunchService(appLaunchService)
    , m_cgroup(new CgroupManager(this)) {
    // A previous shell session's app cgroups (and any frozen orphan pids
    // inside them) outlive greetd restarts — reap them before the first
    // launch of this session can inherit a stale freeze=1.
    if (m_cgroup->isAvailable())
        m_cgroup->reconcileStaleAppCgroups();

    // Apply oom_score bias + cgroup placement as soon as a PID becomes
    // known. Both are best-effort on the dev box (procfs and cgroup writes
    // may be denied) but reliable on the duranium image.
    if (m_appLaunchService) {
        connect(m_appLaunchService, &AppLaunchService::pidRegistered, this,
                [this](qint64 pid, const QString &appId) {
                    // Runner-based apps (marathon-app-runner subprocess)
                    // never call the shell-side registerApp() because
                    // their MApp QObject lives in the subprocess, not the
                    // shell. Seed their lifecycle state on the pid edge
                    // so uclamp/OOM/freeze all have a state to key off.
                    // The user just tapped the icon so Foreground is the
                    // correct initial state.
                    if (!m_appStates.contains(appId)) {
                        AppState st;
                        st.launchTimeMs   = QDateTime::currentMSecsSinceEpoch();
                        st.stateEnteredMs = st.launchTimeMs;
                        st.state          = Foreground;
                        m_appStates.insert(appId, st);
                    }
                    // Demote the previous foreground app so uclamp / OOM
                    // reflect only one Foreground at a time. For runner-
                    // based apps this path substitutes for the demote
                    // that bringToForeground normally does for in-shell
                    // (QObject-registered) apps.
                    if (!m_foregroundAppId.isEmpty() && m_foregroundAppId != appId) {
                        onForegroundExit(m_foregroundAppId);
                    }
                    m_foregroundAppId = appId;
                    if (auto it = m_appStates.find(appId); it != m_appStates.end()) {
                        writeOomScoreAdj(appId, it->state);
                    }
                    if (m_cgroup && m_cgroup->isAvailable()) {
                        m_cgroup->placeAppPid(pid, appId);
                        if (auto it = m_appStates.find(appId); it != m_appStates.end()) {
                            m_cgroup->setAppFrozen(appId, it->state == Frozen);
                            m_cgroup->setAppUclampMin(appId, it->state == Foreground ? 30 : 0);
                        }
                    }
                });
        connect(m_appLaunchService, &AppLaunchService::pidUnregistered, this,
                [this](qint64 pid, const QString &appId) {
                    Q_UNUSED(pid);
                    if (m_cgroup)
                        m_cgroup->removeAppCgroup(appId);
                });
    }
}

void AppLifecycleManager::registerApp(const QString &appId, QObject *appInstance) {
    if (appId.isEmpty() || !appInstance)
        return;

    m_appRegistry.insert(appId, appInstance);
    emit appRegistered(appId, appInstance);

    auto it = m_appStates.find(appId);
    if (it == m_appStates.end()) {
        AppState st;
        st.launchTimeMs   = QDateTime::currentMSecsSinceEpoch();
        st.stateEnteredMs = st.launchTimeMs;
        st.state          = BackgroundIdle;
        m_appStates.insert(appId, st);
    }

    if (m_pendingForegroundApps.contains(appId)) {
        m_pendingForegroundApps.removeAll(appId);
        bringToForeground(appId);
    }

    ensureTaskExists(appId);
}

void AppLifecycleManager::unregisterApp(const QString &appId) {
    if (appId.isEmpty())
        return;

    if (m_taskModel) {
        if (Task *task = m_taskModel->getTaskByAppId(appId)) {
            m_taskModel->closeTask(task->id());
        }
    }

    cancelIdleFreezeDebounce(appId);

    if (m_appStates.contains(appId)) {
        const LifecycleState old = m_appStates[appId].state;
        if (old != Killed) {
            m_appStates[appId].state          = Killed;
            m_appStates[appId].stateEnteredMs = QDateTime::currentMSecsSinceEpoch();
            emit stateChanged(appId, old, Killed);
        }
    }

    m_appRegistry.remove(appId);
    m_appStates.remove(appId);
    m_pendingForegroundApps.removeAll(appId);
    if (m_foregroundAppId == appId)
        m_foregroundAppId.clear();

    emit appUnregistered(appId);
}

QObject *AppLifecycleManager::getAppInstance(const QString &appId) const {
    return m_appRegistry.value(appId, nullptr);
}

QVariantMap AppLifecycleManager::appInfoFromInstance(const QString &appId,
                                                     QObject       *instance) const {
    QVariantMap info;
    info["appId"]          = appId;
    info["appName"]        = instance ? instance->property("appName") : QVariant();
    info["appIcon"]        = instance ? instance->property("appIcon") : QVariant();
    info["appType"]        = instance ? instance->property("appType") : QVariant();
    info["isNative"]       = instance ? instance->property("isNative") : QVariant();
    info["surfaceId"]      = instance ? instance->property("surfaceId") : QVariant();
    info["waylandSurface"] = instance ? instance->property("waylandSurface") : QVariant();
    return info;
}

void AppLifecycleManager::bringToForeground(const QString &appId) {
    if (appId.isEmpty())
        return;

    // Demote the prior foreground app: BackgroundActive if it holds a
    // capability (music playing, call active, nav running), else BgIdle.
    if (!m_foregroundAppId.isEmpty() && m_foregroundAppId != appId) {
        if (QObject *prev = m_appRegistry.value(m_foregroundAppId)) {
            invokeVoid(prev, "pause");
            invokeVoid(prev, "stop");
        }
        onForegroundExit(m_foregroundAppId);
    }

    if (QObject *app = m_appRegistry.value(appId)) {
        invokeVoid(app, "start");
        invokeVoid(app, "resume");

        m_foregroundAppId = appId;
        if (m_appStates.contains(appId)) {
            auto &st        = m_appStates[appId];
            st.isActive     = true;
            st.isPaused     = false;
            st.isMinimized  = false;
            st.lastActiveMs = QDateTime::currentMSecsSinceEpoch();
        }
        cancelIdleFreezeDebounce(appId);
        transitionTo(appId, Foreground);
        ensureTaskExists(appId);
    } else {
        if (!m_pendingForegroundApps.contains(appId))
            m_pendingForegroundApps.push_back(appId);
    }
}

void AppLifecycleManager::restoreApp(const QString &appId) {
    if (QObject *app = m_appRegistry.value(appId)) {
        invokeVoid(app, "restore");
        bringToForeground(appId);
    }
}

void AppLifecycleManager::launchAppWithRoute(const QString &appId, const QString &route,
                                             const QString &paramsJson) {
    if (!m_appLaunchService)
        return;
    QMetaObject::invokeMethod(m_appLaunchService, "launchAppWithRoute", Qt::DirectConnection,
                              Q_ARG(QVariant, QVariant(appId)), Q_ARG(QString, route),
                              Q_ARG(QString, paramsJson), Q_ARG(QObject *, nullptr),
                              Q_ARG(QObject *, nullptr));
}

bool AppLifecycleManager::handleSystemBack() {
    if (m_foregroundAppId.isEmpty())
        return false;

    // Marathon apps launch as a separate marathon-app-runner process; the
    // shell does NOT hold a QObject for them in m_appRegistry (the MApp
    // root lives in the runner). Route the back gesture over DBus to the
    // runner first — its app-side MAppRouter pops the nav stack if it has
    // depth, or surfaces an unhandled response so we can minimise the app.
    if (m_appLaunchService && m_appLaunchService->isMarathonAppId(m_foregroundAppId))
        return m_appLaunchService->sendBackToRunner(m_foregroundAppId);

    QObject *app = m_appRegistry.value(m_foregroundAppId);
    if (!app)
        return false;

    const bool isNative = app->property("isNative").toBool();
    if (isNative) {
        QObject *compositor = m_appLaunchService ? m_appLaunchService->compositor() : nullptr;
        if (compositor) {
            if (invokeInjectKey(compositor, 0x01000000, 0, true) &&
                invokeInjectKey(compositor, 0x01000000, 0, false)) {
                return true;
            }
        }
        return false;
    }

    bool handled = false;
    invokeBool(app, "handleBack", &handled);
    return handled;
}

bool AppLifecycleManager::handleSystemForward() {
    if (m_foregroundAppId.isEmpty())
        return false;

    // Marathon apps live in marathon-app-runner; route forward via DBus
    // before consulting the local m_appRegistry. See handleSystemBack().
    if (m_appLaunchService && m_appLaunchService->isMarathonAppId(m_foregroundAppId))
        return m_appLaunchService->sendForwardToRunner(m_foregroundAppId);

    QObject *app = m_appRegistry.value(m_foregroundAppId);
    if (!app)
        return false;

    const bool isNative = app->property("isNative").toBool();
    if (isNative) {
        QObject *compositor = m_appLaunchService ? m_appLaunchService->compositor() : nullptr;
        if (compositor) {
            if (invokeInjectKey(compositor, 0x01000014, 0x08000000, true) &&
                invokeInjectKey(compositor, 0x01000014, 0x08000000, false)) {
                return true;
            }
        }
        return false;
    }

    bool handled = false;
    invokeBool(app, "handleForward", &handled);
    return handled;
}

bool AppLifecycleManager::minimizeForegroundApp() {
    if (m_foregroundAppId.isEmpty())
        return false;

    const QString appId = m_foregroundAppId;
    ensureTaskExists(appId);

    if (QObject *app = m_appRegistry.value(appId)) {
        invokeVoid(app, "minimize");
        invokeVoid(app, "stop");
    }

    if (m_appStates.contains(appId)) {
        auto &st       = m_appStates[appId];
        st.isMinimized = true;
        st.isActive    = false;
    }

    m_foregroundAppId.clear();
    onForegroundExit(appId);
    return true;
}

void AppLifecycleManager::broadcastLowMemory() {
    for (auto it = m_appRegistry.constBegin(); it != m_appRegistry.constEnd(); ++it) {
        if (it.value())
            invokeVoid(it.value(), "handleLowMemory");
    }
}

void AppLifecycleManager::closeApp(const QString &appId, bool skipNativeClose) {
    if (appId.isEmpty())
        return;

    if (m_taskModel) {
        if (Task *task = m_taskModel->getTaskByAppId(appId)) {
            m_taskModel->closeTask(task->id());
        }
    }

    QObject *app = m_appRegistry.value(appId);
    if (app) {
        const int surfaceId = app->property("surfaceId").toInt();
        if (!skipNativeClose && surfaceId > 0 && m_appLaunchService) {
            m_appLaunchService->closeNativeApp(surfaceId);
        }
        invokeVoid(app, "close");
    }

    if (m_foregroundAppId == appId)
        m_foregroundAppId.clear();

    unregisterApp(appId);
}

QVariantMap AppLifecycleManager::getAppState(const QString &appId) const {
    if (!m_appStates.contains(appId))
        return {};
    const auto &st = m_appStates[appId];
    return {
        {"appId", appId},
        {"state", static_cast<int>(st.state)},
        {"isActive", st.isActive},
        {"isPaused", st.isPaused},
        {"isMinimized", st.isMinimized},
        {"launchTime", st.launchTimeMs},
        {"lastActiveTime", st.lastActiveMs},
        {"stateEnteredTime", st.stateEnteredMs},
        {"capabilities", QStringList(st.capabilities.cbegin(), st.capabilities.cend())},
    };
}

bool AppLifecycleManager::isAppRunning(const QString &appId) const {
    return m_appRegistry.contains(appId);
}

QString AppLifecycleManager::getForegroundAppId() const {
    return m_foregroundAppId.isEmpty() ? QString() : m_foregroundAppId;
}

int AppLifecycleManager::lifecycleState(const QString &appId) const {
    if (!m_appStates.contains(appId))
        return static_cast<int>(Unregistered);
    return static_cast<int>(m_appStates[appId].state);
}

QStringList AppLifecycleManager::activeCapabilities(const QString &appId) const {
    if (!m_appStates.contains(appId))
        return {};
    const auto &caps = m_appStates[appId].capabilities;
    return QStringList(caps.cbegin(), caps.cend());
}

void AppLifecycleManager::addCapability(const QString &appId, const QString &capability) {
    if (appId.isEmpty() || capability.isEmpty())
        return;
    auto it = m_appStates.find(appId);
    if (it == m_appStates.end())
        return;
    if (it->capabilities.contains(capability))
        return;
    it->capabilities.insert(capability);
    qCInfo(lcLifecycle) << "capability +" << capability << "for" << appId << "now:"
                        << QStringList(it->capabilities.cbegin(), it->capabilities.cend());
    emit capabilitiesChanged(appId);

    // A backgrounded app that just gained a capability shouldn't freeze.
    // Promote it from BgIdle → BgActive and cancel any pending freeze.
    if (it->state == BackgroundIdle) {
        cancelIdleFreezeDebounce(appId);
        transitionTo(appId, BackgroundActive);
    }
}

void AppLifecycleManager::removeCapability(const QString &appId, const QString &capability) {
    if (appId.isEmpty() || capability.isEmpty())
        return;
    auto it = m_appStates.find(appId);
    if (it == m_appStates.end())
        return;
    if (!it->capabilities.remove(capability))
        return;
    qCInfo(lcLifecycle) << "capability -" << capability << "for" << appId << "now:"
                        << QStringList(it->capabilities.cbegin(), it->capabilities.cend());
    emit capabilitiesChanged(appId);

    // Last capability cleared while backgrounded → drop to BgIdle and arm
    // the freeze debounce. Foreground apps are unaffected (they don't
    // freeze regardless of caps).
    if (it->state == BackgroundActive && it->capabilities.isEmpty()) {
        transitionTo(appId, BackgroundIdle);
        startIdleFreezeDebounce(appId);
    }
}

void AppLifecycleManager::setIdleFreezeDebounceMs(int ms) {
    m_idleFreezeDebounceMs = qMax(0, ms);
}

void AppLifecycleManager::onForegroundExit(const QString &appId) {
    if (appId.isEmpty())
        return;
    auto it = m_appStates.find(appId);
    if (it == m_appStates.end())
        return;
    it->isActive = false;
    it->isPaused = true;

    // Capability set decides the demotion target: any active capability ⇒
    // BackgroundActive (never frozen); otherwise BackgroundIdle + debounce.
    if (!it->capabilities.isEmpty()) {
        transitionTo(appId, BackgroundActive);
    } else {
        transitionTo(appId, BackgroundIdle);
        startIdleFreezeDebounce(appId);
    }
}

void AppLifecycleManager::startIdleFreezeDebounce(const QString &appId) {
    auto it = m_appStates.find(appId);
    if (it == m_appStates.end())
        return;
    cancelIdleFreezeDebounce(appId);

    if (m_idleFreezeDebounceMs <= 0)
        return;

    QTimer *timer = new QTimer(this);
    timer->setSingleShot(true);
    timer->setInterval(m_idleFreezeDebounceMs);
    const QString &capturedAppId = appId;
    connect(timer, &QTimer::timeout, this, [this, capturedAppId, timer]() {
        auto state = m_appStates.find(capturedAppId);
        if (state == m_appStates.end())
            return;
        if (state->idleFreezeTimer == timer)
            state->idleFreezeTimer = nullptr;
        timer->deleteLater();
        if (state->state == BackgroundIdle) {
            transitionTo(capturedAppId, Frozen);
        }
    });
    it->idleFreezeTimer = timer;
    timer->start();
}

void AppLifecycleManager::cancelIdleFreezeDebounce(const QString &appId) {
    auto it = m_appStates.find(appId);
    if (it == m_appStates.end())
        return;
    if (it->idleFreezeTimer) {
        it->idleFreezeTimer->stop();
        it->idleFreezeTimer->deleteLater();
        it->idleFreezeTimer = nullptr;
    }
}

void AppLifecycleManager::transitionTo(const QString &appId, LifecycleState newState) {
    auto it = m_appStates.find(appId);
    if (it == m_appStates.end())
        return;
    const LifecycleState old = it->state;
    if (old == newState)
        return;
    // Never freeze an app that has not mapped its first surface. Freezing
    // a cold-starting runner stops it before it can create its Wayland
    // toplevel, leaving a permanently invisible process the user reads as
    // "the app won't open" (2026-07-02 audit). Stay in the current state
    // and retry after another debounce window instead.
    if (newState == Frozen) {
        Task *task = m_taskModel ? m_taskModel->getTaskByAppId(appId) : nullptr;
        if (!task || task->surfaceId() < 0) {
            qCInfo(lcLifecycle) << appId << "freeze deferred: no mapped surface yet";
            startIdleFreezeDebounce(appId);
            return;
        }
    }
    it->state          = newState;
    it->stateEnteredMs = QDateTime::currentMSecsSinceEpoch();
    qCInfo(lcLifecycle) << appId << ":" << static_cast<int>(old) << "→"
                        << static_cast<int>(newState);
    writeOomScoreAdj(appId, newState);

    // Cgroup freeze/thaw on the transition boundary. The state machine
    // never freezes an app that's actively holding a capability — the
    // BackgroundActive ↔ BackgroundIdle distinction is what protects
    // music/calls/nav. Any non-Frozen state thaws (cheap to call when
    // already thawed).
    if (m_cgroup && m_cgroup->isAvailable()) {
        if (newState == Frozen) {
            m_cgroup->setAppFrozen(appId, true);
        } else if (old == Frozen) {
            m_cgroup->setAppFrozen(appId, false);
        }
        // cpu.uclamp.min — mainline replacement for Android's ROM-lore
        // "touch boost". Foreground app gets 30 (guarantees ~30% of
        // capacity as a schedutil freq floor while its tasks are
        // runnable); everything else resets to 0 (no boost). This is
        // the right layer to fight ondemand's 100 ms sampling lag on
        // interactive load spikes.
        m_cgroup->setAppUclampMin(appId, newState == Foreground ? 30 : 0);
    }

    emit stateChanged(appId, static_cast<int>(old), static_cast<int>(newState));
}

int AppLifecycleManager::oomScoreForState(LifecycleState state) {
    // oom_score_adj range is [-1000, 1000]. Lower = less likely to be
    // killed by the kernel OOM killer / systemd-oomd. Values below taken
    // from Android's ProcessList ladder
    // (FOREGROUND_APP_ADJ=0, PERCEPTIBLE/VISIBLE bands ~100-200, CACHED
    // band 900-999) plus the iOS jetsam rule that an audio/nav/call app
    // outranks a merely-visible one (jetsam priority Audio=12 > Foreground=10).
    //
    // The shell itself writes oom_score_adj=-800 in main.cpp (PERSISTENT_PROC
    // equivalent). The values here are for app-runner subprocesses.
    switch (state) {
        // Visible app; recoverable on cold relaunch.
        case Foreground: return 0;
        // Holding an active capability (audio playback, navigation,
        // active call, recording). iOS protects these OVER the foreground
        // app — interrupting music to keep an idle visible tab alive is
        // a UX disaster. Marathon does the same.
        case BackgroundActive: return -100;
        // Backgrounded, no capabilities, within the freeze debounce window.
        // Above-foreground oom_score but below cached, so the kernel will
        // pick frozen apps first under pressure.
        case BackgroundIdle: return 300;
        // Frozen via cgroup.freeze. Eligible for kernel kill; we also
        // kill oldest-frozen-first from MemoryPressureMonitor at Critical.
        case Frozen: return 950;
        case Killed:
        case Unregistered: return 0;
    }
    return 0;
}

int AppLifecycleManager::killOldestFrozenApp() {
    QString oldestId;
    qint64  oldestEnter = std::numeric_limits<qint64>::max();
    for (auto it = m_appStates.constBegin(); it != m_appStates.constEnd(); ++it) {
        if (it.value().state != Frozen)
            continue;
        if (it.value().stateEnteredMs < oldestEnter) {
            oldestEnter = it.value().stateEnteredMs;
            oldestId    = it.key();
        }
    }
    if (oldestId.isEmpty()) {
        qCInfo(lcLifecycle) << "killOldestFrozenApp: no frozen apps to kill";
        return -1;
    }
    if (!m_appLaunchService) {
        qCWarning(lcLifecycle) << "killOldestFrozenApp: no AppLaunchService";
        return -1;
    }
    const qint64 pid = m_appLaunchService->pidForAppId(oldestId);
    if (pid <= 0) {
        qCWarning(lcLifecycle) << "killOldestFrozenApp: no PID for" << oldestId;
        return -1;
    }
    qCInfo(lcLifecycle) << "killOldestFrozenApp: SIGTERM pid" << pid << "appId=" << oldestId
                        << "(frozen for"
                        << (QDateTime::currentMSecsSinceEpoch() - oldestEnter) / 1000 << "s)";
    // Thaw before SIGTERM so the app can run its cleanup / cgroup.freeze=1
    // would otherwise block the signal handler from executing.
    if (m_cgroup && m_cgroup->isAvailable())
        m_cgroup->setAppFrozen(oldestId, false);
    ::kill(static_cast<pid_t>(pid), SIGTERM);
    // SIGKILL fallback if the app doesn't exit cleanly.
    QPointer<AppLifecycleManager> self(this);
    QTimer::singleShot(5000, this, [self, oldestId, pid]() {
        if (!self)
            return;
        if (self->m_appLaunchService && self->m_appLaunchService->pidForAppId(oldestId) == pid) {
            qCInfo(lcLifecycle) << "killOldestFrozenApp: SIGKILL pid" << pid
                                << "(SIGTERM grace expired)";
            ::kill(static_cast<pid_t>(pid), SIGKILL);
        }
    });
    transitionTo(oldestId, Killed);
    return static_cast<int>(pid);
}

void AppLifecycleManager::writeOomScoreAdj(const QString &appId, LifecycleState state) {
    if (!m_appLaunchService)
        return;
    const qint64 pid = m_appLaunchService->pidForAppId(appId);
    if (pid <= 0)
        return;
    const int score = oomScoreForState(state);
    QFile     f(QStringLiteral("/proc/%1/oom_score_adj").arg(pid));
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCDebug(lcLifecycle) << "oom_score_adj write skipped for" << appId << "pid" << pid
                             << "(open failed:" << f.errorString() << ")";
        return;
    }
    f.write(QByteArray::number(score));
    f.close();
    qCDebug(lcLifecycle) << "oom_score_adj=" << score << "for" << appId << "pid" << pid;
}

bool AppLifecycleManager::ensureTaskExists(const QString &appId) {
    if (!m_taskModel)
        return false;
    if (Task *task = m_taskModel->getTaskByAppId(appId))
        return task != nullptr;

    QObject *instance = m_appRegistry.value(appId);
    if (!instance)
        return false;

    const QString name = instance->property("appName").toString().isEmpty() ?
        appId :
        instance->property("appName").toString();
    const QString icon = instance->property("appIcon").toString();
    const QString type = instance->property("appType").toString().isEmpty() ?
        QStringLiteral("marathon") :
        instance->property("appType").toString();
    const int     surfaceId =
        instance->property("surfaceId").isValid() ? instance->property("surfaceId").toInt() : -1;
    QObject *surface = instance->property("waylandSurface").value<QObject *>();

    m_taskModel->launchTask(appId, name, icon, type, surfaceId, surface);
    return true;
}

bool AppLifecycleManager::invokeVoid(QObject *obj, const char *method) {
    if (!obj)
        return false;
    return QMetaObject::invokeMethod(obj, method, Qt::DirectConnection);
}

bool AppLifecycleManager::invokeBool(QObject *obj, const char *method, bool *out) {
    if (!obj)
        return false;
    QVariant   ret;
    auto       r  = Q_RETURN_ARG(QVariant, ret);
    const bool ok = QMetaObject::invokeMethod(obj, method, Qt::DirectConnection, r);
    if (ok && out)
        *out = ret.toBool();
    return ok;
}

bool AppLifecycleManager::invokeInjectKey(QObject *compositor, int key, int modifiers,
                                          bool pressed) {
    if (!compositor)
        return false;
    return QMetaObject::invokeMethod(compositor, "injectKey", Qt::DirectConnection, Q_ARG(int, key),
                                     Q_ARG(int, modifiers), Q_ARG(bool, pressed));
}
