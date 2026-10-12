#ifndef MUSICLIBRARYMANAGER_H
#define MUSICLIBRARYMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QThread>
#include <QThreadPool>

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

// Walks the music folders and writes the tracks table on its own thread and
// database connection, committing in batches.
class MusicScanWorker : public QObject {
    Q_OBJECT
  public:
    MusicScanWorker(const QStringList &paths, const QString &dbPath, QObject *parent = nullptr);

  public slots:
    void process();

  signals:
    void scanProgress(int current, int total);
    void batchStored(int trackCount);
    void scanFinished(int trackCount, const QList<Artist> &artists);

  private:
    QStringList              m_paths;
    QString                  m_dbPath;
    Track                    scanFile(const QString &filePath);

    static const QStringList &audioExtensions();
};

class MusicLibraryManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList artists READ artists NOTIFY libraryChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY libraryChanged)
    Q_PROPERTY(int scanProgress READ scanProgress NOTIFY scanProgressChanged)

  public:
    explicit MusicLibraryManager(QObject *parent = nullptr);
    ~MusicLibraryManager() override;

    QVariantList             artists() const;
    bool                     isScanning() const;
    int                      trackCount() const;
    int                      scanProgress() const;

    Q_INVOKABLE void         scanLibraryAsync();
    // Emits tracksLoaded with every track; the query runs off the GUI thread.
    Q_INVOKABLE void         loadTracksAsync();

  signals:
    void libraryChanged();
    void scanningChanged(bool scanning);
    void scanComplete(int trackCount);
    void scanProgressChanged(int progress);
    void tracksLoaded(const QVariantList &tracks);

  private slots:
    void onDirectoryChanged(const QString &path);
    void onScanFinished(int trackCount, const QList<Artist> &artists);
    void onScanProgress(int current, int total);

  private:
    void                     initDatabase();
    QStringList              getScanPaths();

    QList<Artist>            m_artists;
    QString                  m_dbPath;
    QFileSystemWatcher      *m_watcher;
    QTimer                  *m_scanTimer;
    QThread                 *m_scanThread;
    MusicScanWorker         *m_scanWorker;
    bool                     m_isScanning;
    int                      m_trackCount;
    int                      m_scanProgress;
    int                      m_loadGeneration;
    QThreadPool              m_readers;
};

#endif
