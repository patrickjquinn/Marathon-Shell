#ifndef MPRIS2CONTROLLER_H
#define MPRIS2CONTROLLER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QTimer>
#include <QMap>
#include <QVariantMap>

/**
 * MPRIS2Controller - Control media players via MPRIS2 D-Bus interface
 * 
 * Monitors all media players (Spotify, VLC, Firefox, Chromium, etc.)
 * and provides unified playback control.
 * 
 * MPRIS2 spec: https://specifications.freedesktop.org/mpris-spec/latest/
 */
class MPRIS2Controller : public QObject
{
    Q_OBJECT
    
    // Player state
    Q_PROPERTY(bool hasActivePlayer READ hasActivePlayer NOTIFY activePlayerChanged)
    Q_PROPERTY(QString playerName READ playerName NOTIFY activePlayerChanged)
    Q_PROPERTY(QString playbackStatus READ playbackStatus NOTIFY playbackStatusChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playbackStatusChanged)
    Q_PROPERTY(bool isPaused READ isPaused NOTIFY playbackStatusChanged)
    Q_PROPERTY(QString desktopEntry READ desktopEntry NOTIFY activePlayerChanged)
    
    // Metadata
    Q_PROPERTY(QString trackTitle READ trackTitle NOTIFY metadataChanged)
    Q_PROPERTY(QString trackArtist READ trackArtist NOTIFY metadataChanged)
    Q_PROPERTY(QString trackAlbum READ trackAlbum NOTIFY metadataChanged)
    Q_PROPERTY(QString albumArtUrl READ albumArtUrl NOTIFY metadataChanged)
    Q_PROPERTY(qint64 trackLength READ trackLength NOTIFY metadataChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    
    // Capabilities
    Q_PROPERTY(bool canPlay READ canPlay NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canPause READ canPause NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY capabilitiesChanged)

public:
    explicit MPRIS2Controller(QObject *parent = nullptr);
    ~MPRIS2Controller();

    // Property getters
    bool hasActivePlayer() const { return m_hasActivePlayer; }
    QString playerName() const { return m_playerName; }
    QString playbackStatus() const { return m_playbackStatus; }
    bool isPlaying() const { return m_playbackStatus == "Playing"; }
    bool isPaused() const { return m_playbackStatus == "Paused"; }
    QString desktopEntry() const { return m_desktopEntry; }
    
    QString trackTitle() const { return m_trackTitle; }
    QString trackArtist() const { return m_trackArtist; }
    QString trackAlbum() const { return m_trackAlbum; }
    QString albumArtUrl() const { return m_albumArtUrl; }
    qint64 trackLength() const { return m_trackLength; }
    qint64 position() const { return m_position; }
    
    bool canPlay() const { return m_canPlay; }
    bool canPause() const { return m_canPause; }
    bool canGoNext() const { return m_canGoNext; }
    bool canGoPrevious() const { return m_canGoPrevious; }
    bool canSeek() const { return m_canSeek; }

public slots:
    // Playback control
    void play();
    void pause();
    void playPause();
    void stop();
    void next();
    void previous();
    void seek(qint64 offset);
    void setPosition(qint64 position);
    
    // Player management
    void scanForPlayers();
    void switchToPlayer(const QString& busName);

signals:
    void activePlayerChanged();
    void playbackStatusChanged();
    void metadataChanged();
    void positionChanged();
    void capabilitiesChanged();
    void playerListChanged(const QStringList& players);

private slots:
    void updatePlaybackStatus();
    void updateMetadata();
    void updatePosition();
    void updateCapabilities();
    void onDBusServiceRegistered(const QString& serviceName);
    void onDBusServiceUnregistered(const QString& serviceName);

private:
    void connectToPlayer(const QString& busName);
    void disconnectFromPlayer();
    void setupDBusMonitoring();
    QString extractMetadataString(const QVariantMap& metadata, const QString& key);
    qint64 extractMetadataInt64(const QVariantMap& metadata, const QString& key);
    QStringList extractMetadataStringList(const QVariantMap& metadata, const QString& key);
    
    // D-Bus interfaces
    QDBusInterface* m_playerInterface;
    QTimer* m_positionTimer;
    QTimer* m_scanTimer;
    
    // Current player state
    QString m_currentBusName;
    bool m_hasActivePlayer;
    QString m_playerName;
    QString m_desktopEntry;
    QString m_playbackStatus;
    
    // Metadata
    QString m_trackTitle;
    QString m_trackArtist;
    QString m_trackAlbum;
    QString m_albumArtUrl;
    qint64 m_trackLength;
    qint64 m_position;
    
    // Capabilities
    bool m_canPlay;
    bool m_canPause;
    bool m_canGoNext;
    bool m_canGoPrevious;
    bool m_canSeek;
    
    // Available players
    QStringList m_availablePlayers;
};

#endif // MPRIS2CONTROLLER_H

