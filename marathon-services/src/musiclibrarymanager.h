#ifndef MUSICLIBRARYMANAGER_H
#define MUSICLIBRARYMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QThread>
#include <QMutex>

struct Track {
    int     id;
    QString path;
    QString title;
    QString artist;
    QString album;
    int     duration;
    int     trackNumber;
    QString year;
};

struct Artist {
    QString name;
    int     albumCount;
    int     trackCount;
};

// Worker thread for async music scanning
class MusicScanWorker : public QObject {
    Q_OBJECT
  public:
    explicit MusicScanWorker(const QStringList &paths, QObject *parent = nullptr);

  public slots:
    void process();

  signals:
    void scanProgress(int current, int total);
    void scanFinished(QList<Track> tracks);
    void scanError(QString error);

  private:
    QStringList              m_paths;
    bool                     isAudioFile(const QString &path);
    Track                    scanFile(const QString &filePath);

    static const QStringList AUDIO_EXTENSIONS;
};

class MusicLibraryManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList artists READ artists NOTIFY libraryChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY libraryChanged)
    Q_PROPERTY(int scanProgress READ scanProgress NOTIFY scanProgressChanged)

  public:
    explicit MusicLibraryManager(QObject *parent = nullptr);
    ~MusicLibraryManager();

    QVariantList             artists() const;
    bool                     isScanning() const;
    int                      trackCount() const;
    int                      scanProgress() const;

    Q_INVOKABLE void         scanLibrary();
    Q_INVOKABLE void         scanLibraryAsync(); // New async method
    Q_INVOKABLE QVariantList getAlbums(const QString &artistName);
    Q_INVOKABLE QVariantList getTracks(const QString &albumName);
    Q_INVOKABLE QVariantList getAllTracks();
    Q_INVOKABLE QVariantMap  getTrackMetadata(int trackId);

  signals:
    void libraryChanged();
    void scanningChanged(bool scanning);
    void scanComplete(int trackCount);
    void scanProgressChanged(int progress);

  private slots:
    void onDirectoryChanged(const QString &path);
    void performScan();
    void onScanFinished(QList<Track> tracks);
    void onScanProgress(int current, int total);

  private:
    void                     initDatabase();
    void                     scanDirectory(const QString &path);
    void                     addTrack(const QString &filePath);
    void                     addTrackBatch(const QList<Track> &tracks); // Batch insert
    void                     extractMetadata(const QString &path, Track &track);
    void                     loadArtists();
    bool                     isAudioFile(const QString &path);
    QStringList              getScanPaths();

    QList<Artist>            m_artists;
    QSqlDatabase             m_database;
    QFileSystemWatcher      *m_watcher;
    QTimer                  *m_scanTimer;
    QThread                 *m_scanThread;
    MusicScanWorker         *m_scanWorker;
    bool                     m_isScanning;
    int                      m_trackCount;
    int                      m_scanProgress;
    mutable QMutex           m_mutex;

    static const QStringList AUDIO_EXTENSIONS;
};

#endif // MUSICLIBRARYMANAGER_H
