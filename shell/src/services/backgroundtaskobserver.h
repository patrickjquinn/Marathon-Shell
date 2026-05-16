#pragma once

#include <QObject>
#include <QPointer>
#include <QString>

class AppLifecycleManager;
class AppLaunchService;
class MPRIS2Controller;
class TelephonyService;

// Bridges system-observed activity signals into AppLifecycleManager
// capability claims. Today it covers two cases:
//   - MPRIS2 (audio-playback)  — resolves the publisher bus name to a
//     PID via org.freedesktop.DBus.GetConnectionUnixProcessID, then
//     to an appId via AppLaunchService::appIdForPid.
//   - Telephony (active-call) — hard-wired to the "phone" appId for
//     now; a future VoIP integration would feed app-declared claims
//     instead via BeginBackgroundTask DBus (Phase B).
class BackgroundTaskObserver : public QObject {
    Q_OBJECT

  public:
    BackgroundTaskObserver(AppLifecycleManager *lifecycle, AppLaunchService *launch,
                           MPRIS2Controller *mpris, TelephonyService *telephony,
                           QObject *parent = nullptr);

  private:
    void                          onMprisPlaybackChanged();
    void                          onMprisActivePlayerChanged();
    void                          onCallStateChanged(const QString &state);

    void                          claimAudioPlaybackFor(const QString &appId);
    void                          releaseAudioPlayback();

    QString                       resolveAppIdForBusName(const QString &busName) const;

    QPointer<AppLifecycleManager> m_lifecycle;
    QPointer<AppLaunchService>    m_launch;
    QPointer<MPRIS2Controller>    m_mpris;
    QPointer<TelephonyService>    m_telephony;

    // Track who's currently holding each capability so we can release it
    // correctly when the source signal flips, even if the active player
    // / app changes mid-flight.
    QString m_audioPlaybackAppId;
    QString m_activeCallAppId;
};
