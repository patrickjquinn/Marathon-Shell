#ifndef MPRIS2CONTROLLER_H
#define MPRIS2CONTROLLER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QDBusContext>
#include <QDBusMessage>
#include <QTimer>
#include <QVariantMap>
#include <functional>
#include <qqml.h>

// Every D-Bus call here is asynchronous: a player can be busy, or blocked
// on the compositor (a GTK client's wl_display_roundtrip before its first
// map), and a blocking call from the GUI thread would deadlock the shell.
class MPRIS2Controller : public QObject, protected QDBusContext {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool hasActivePlayer READ hasActivePlayer NOTIFY activePlayerChanged)
    Q_PROPERTY(QString playerName READ playerName NOTIFY activePlayerChanged)
    Q_PROPERTY(QString playbackStatus READ playbackStatus NOTIFY playbackStatusChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playbackStatusChanged)
    Q_PROPERTY(bool isPaused READ isPaused NOTIFY playbackStatusChanged)
    Q_PROPERTY(QString desktopEntry READ desktopEntry NOTIFY activePlayerChanged)

    Q_PROPERTY(QString trackTitle READ trackTitle NOTIFY metadataChanged)
    Q_PROPERTY(QString trackArtist READ trackArtist NOTIFY metadataChanged)
    Q_PROPERTY(QString trackAlbum READ trackAlbum NOTIFY metadataChanged)
    Q_PROPERTY(QString albumArtUrl READ albumArtUrl NOTIFY metadataChanged)
    Q_PROPERTY(qint64 trackLength READ trackLength NOTIFY metadataChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)

    Q_PROPERTY(bool canPlay READ canPlay NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canPause READ canPause NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY capabilitiesChanged)

  public:
    explicit MPRIS2Controller(QObject *parent = nullptr);
    ~MPRIS2Controller() override;

    bool hasActivePlayer() const {
        return m_hasActivePlayer;
    }
    QString playerName() const {
        return m_playerName;
    }
    QString currentBusName() const {
        return m_currentBusName;
    }
    QString playbackStatus() const {
        return m_playbackStatus;
    }
    bool isPlaying() const {
        return m_playbackStatus == "Playing";
    }
    bool isPaused() const {
        return m_playbackStatus == "Paused";
    }
    QString desktopEntry() const {
        return m_desktopEntry;
    }

    QString trackTitle() const {
        return m_trackTitle;
    }
    QString trackArtist() const {
        return m_trackArtist;
    }
    QString trackAlbum() const {
        return m_trackAlbum;
    }
    QString albumArtUrl() const {
        return m_albumArtUrl;
    }
    qint64 trackLength() const {
        return m_trackLength;
    }
    qint64 position() const {
        return m_position;
    }

    bool canPlay() const {
        return m_canPlay;
    }
    bool canPause() const {
        return m_canPause;
    }
    bool canGoNext() const {
        return m_canGoNext;
    }
    bool canGoPrevious() const {
        return m_canGoPrevious;
    }
    bool canSeek() const {
        return m_canSeek;
    }

  public slots:

    void play();
    void pause();
    void playPause();
    void stop();
    void next();
    void previous();
    void seek(qint64 offset);
    void setPosition(qint64 position);

    void scanForPlayers();

  signals:
    void activePlayerChanged();
    void playbackStatusChanged();
    void metadataChanged();
    void positionChanged();
    void capabilitiesChanged();
    void playerListChanged(const QStringList &players);

  private slots:
    void onPropertiesChanged(const QString &interfaceName, const QVariantMap &changedProperties,
                             const QStringList &invalidatedProperties);
    void onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);

  private:
    void            callAsync(const QDBusMessage                            &call,
                              const std::function<void(const QDBusMessage &)> &onReply);
    void            callPlayer(const QString &method, const QVariantList &args = {});
    void            getAll(const QString &interface);
    void            refreshSoon();
    void            pollPosition();
    void            onPlayerList(const QStringList &names);
    void            connectToPlayer(const QString &busName);
    void            disconnectFromPlayer();
    void            applyRootProperties(const QVariantMap &props);
    void            applyPlayerProperties(const QVariantMap &props);
    void            applyMetadata(const QVariantMap &metadata);

    QTimer         *m_positionTimer;
    bool            m_positionInFlight = false;

    QString         m_currentBusName;
    QString         m_currentOwner;
    QString         m_trackId;
    bool            m_hasActivePlayer;
    QString         m_playerName;
    QString         m_desktopEntry;
    QString         m_playbackStatus;

    QString         m_trackTitle;
    QString         m_trackArtist;
    QString         m_trackAlbum;
    QString         m_albumArtUrl;
    qint64          m_trackLength;
    qint64          m_position;

    bool            m_canPlay;
    bool            m_canPause;
    bool            m_canGoNext;
    bool            m_canGoPrevious;
    bool            m_canSeek;

    QStringList     m_availablePlayers;
};

#endif
