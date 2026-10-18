#pragma once

// clazy:excludeall=qproperty-without-notify (D-Bus properties; QtDBus has no NOTIFY)

#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QObject>
#include <QQmlEngine>
#include <QQmlParserStatus>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

// Publishes the player as org.mpris.MediaPlayer2 on the session bus while
// `active`, so the shell's media controls and background-audio observer see it.
// Positions and lengths are in milliseconds here and microseconds on the bus.
class MprisPlayerAdaptor;

class MprisPlayer : public QObject, public QQmlParserStatus {
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)

    Q_PROPERTY(bool active MEMBER m_active NOTIFY activeChanged)
    Q_PROPERTY(QString identity MEMBER m_identity CONSTANT)
    Q_PROPERTY(QString desktopEntry MEMBER m_desktopEntry CONSTANT)
    Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged)

    Q_PROPERTY(bool playing MEMBER m_playing NOTIFY statusChanged)
    Q_PROPERTY(bool shuffle MEMBER m_shuffle NOTIFY statusChanged)
    Q_PROPERTY(QString repeatMode MEMBER m_repeatMode NOTIFY statusChanged)
    Q_PROPERTY(bool canGoNext MEMBER m_canGoNext NOTIFY statusChanged)
    Q_PROPERTY(bool canGoPrevious MEMBER m_canGoPrevious NOTIFY statusChanged)

    Q_PROPERTY(int trackId MEMBER m_trackId NOTIFY metadataChanged)
    Q_PROPERTY(QString title MEMBER m_title NOTIFY metadataChanged)
    Q_PROPERTY(QString artist MEMBER m_artist NOTIFY metadataChanged)
    Q_PROPERTY(QString album MEMBER m_album NOTIFY metadataChanged)
    Q_PROPERTY(QString artUrl MEMBER m_artUrl NOTIFY metadataChanged)
    Q_PROPERTY(qint64 length MEMBER m_length NOTIFY metadataChanged)
    Q_PROPERTY(qint64 position MEMBER m_position NOTIFY positionChanged)

  public:
    explicit MprisPlayer(QObject *parent = nullptr);
    ~MprisPlayer() override;

    void            classBegin() override {}
    void            componentComplete() override;

    bool            registered() const {
        return m_registered;
    }

  signals:
    void activeChanged();
    void registeredChanged();
    void statusChanged();
    void metadataChanged();
    void positionChanged();

    void raiseRequested();
    void playRequested();
    void pauseRequested();
    void playPauseRequested();
    void stopRequested();
    void nextRequested();
    void previousRequested();
    void seekRequested(qint64 position);
    void shuffleRequested(bool shuffle);
    void repeatModeRequested(const QString &mode);

  private:
    friend class MprisRootAdaptor;
    friend class MprisPlayerAdaptor;

    QString         playbackStatus() const;
    QString         loopStatus() const;
    QVariantMap     metadata() const;
    QDBusObjectPath trackPath() const;
    void            updateRegistration();
    void            queueChanged(const QString &property);
    void            flushChanges();

    bool            m_complete   = false;
    bool            m_active     = false;
    bool            m_registered = false;
    QString         m_identity{QStringLiteral("Music")};
    QString         m_desktopEntry{QStringLiteral("music")};
    bool            m_playing       = false;
    bool            m_shuffle       = false;
    QString         m_repeatMode{QStringLiteral("off")};
    bool            m_canGoNext     = false;
    bool            m_canGoPrevious = false;
    int             m_trackId       = -1;
    QString         m_title;
    QString         m_artist;
    QString         m_album;
    QString         m_artUrl;
    qint64          m_length   = 0;
    qint64          m_position = 0;

    QSet<QString>   m_dirty;
    QTimer          m_flush;
    MprisPlayerAdaptor *m_playerAdaptor = nullptr;
};

class MprisRootAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ canQuit)
    Q_PROPERTY(bool CanRaise READ canRaise)
    Q_PROPERTY(bool HasTrackList READ hasTrackList)
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
    Q_PROPERTY(QStringList SupportedUriSchemes READ supported)
    Q_PROPERTY(QStringList SupportedMimeTypes READ supported)

  public:
    explicit MprisRootAdaptor(MprisPlayer *player);

    bool canQuit() const {
        return false;
    }
    bool canRaise() const {
        return true;
    }
    bool hasTrackList() const {
        return false;
    }
    QString     identity() const;
    QString     desktopEntry() const;
    QStringList supported() const {
        return {};
    }

  public slots:
    void Raise();
    void Quit() {}

  private:
    MprisPlayer *m_player;
};

class MprisPlayerAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(QString LoopStatus READ loopStatus WRITE setLoopStatus)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(bool Shuffle READ shuffle WRITE setShuffle)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double MinimumRate READ rate)
    Q_PROPERTY(double MaximumRate READ rate)
    Q_PROPERTY(bool CanGoNext READ canGoNext)
    Q_PROPERTY(bool CanGoPrevious READ canGoPrevious)
    Q_PROPERTY(bool CanPlay READ hasTrack)
    Q_PROPERTY(bool CanPause READ hasTrack)
    Q_PROPERTY(bool CanSeek READ hasTrack)
    Q_PROPERTY(bool CanControl READ canControl)

  public:
    explicit MprisPlayerAdaptor(MprisPlayer *player);

    QString     playbackStatus() const;
    QString     loopStatus() const;
    void        setLoopStatus(const QString &status);
    double      rate() const {
        return 1.0;
    }
    void        setRate(double) {}
    bool        shuffle() const;
    void        setShuffle(bool shuffle);
    QVariantMap metadata() const;
    double      volume() const {
        return 1.0;
    }
    void      setVolume(double) {}
    qlonglong position() const;
    bool      canGoNext() const;
    bool      canGoPrevious() const;
    bool      hasTrack() const;
    bool      canControl() const {
        return true;
    }

  public slots:
    void Next();
    void Previous();
    void Pause();
    void PlayPause();
    void Stop();
    void Play();
    void Seek(qlonglong offset);
    void SetPosition(const QDBusObjectPath &trackId, qlonglong position);
    void OpenUri(const QString &) {}

  signals:
    void Seeked(qlonglong position);

  private:
    MprisPlayer *m_player;
};
