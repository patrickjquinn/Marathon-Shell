#ifndef MEDIALIBRARYMANAGER_H
#define MEDIALIBRARYMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QFileSystemWatcher>
#include <QTimer>
#include <QThread>
#include <QMutex>

struct MediaItem {
    int     id;
    QString path;
    QString type;
    QString album;
    qint64  timestamp;
    int     width;
    int     height;
    QString thumbnailPath;
};

struct Album {
    QString id;
    QString name;
    int     photoCount;
    QString coverPath;
    qint64  lastModified;
};

// Worker thread for async scanning
class MediaScanWorker : public QObject {
    Q_OBJECT
  public:
    explicit MediaScanWorker(const QStringList &paths, QObject *parent = nullptr);

  public slots:
    void process();

  signals:
    void scanProgress(int current, int total);
    void scanFinished(QList<MediaItem> items);
    void scanError(QString error);

  private:
    QStringList              m_paths;
    bool                     isImageFile(const QString &path);
    bool                     isVideoFile(const QString &path);
    MediaItem                scanFile(const QString &filePath);

    static const QStringList IMAGE_EXTENSIONS;
    static const QStringList VIDEO_EXTENSIONS;
};

class MediaLibraryManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList albums READ albums NOTIFY albumsChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int photoCount READ photoCount NOTIFY libraryChanged)
    Q_PROPERTY(int videoCount READ videoCount NOTIFY libraryChanged)
    Q_PROPERTY(int scanProgress READ scanProgress NOTIFY scanProgressChanged)

  public:
    explicit MediaLibraryManager(QObject *parent = nullptr);
    ~MediaLibraryManager();

    QVariantList             albums() const;
    bool                     isScanning() const;
    int                      photoCount() const;
    int                      videoCount() const;
    int                      scanProgress() const;

    Q_INVOKABLE void         scanLibrary();
    Q_INVOKABLE void         scanLibraryAsync(); // New async method
    Q_INVOKABLE QVariantList getPhotos(const QString &albumId);
    Q_INVOKABLE QVariantList getVideos();
    Q_INVOKABLE QVariantList getAllPhotos();
    Q_INVOKABLE QString      generateThumbnail(const QString &filePath);
    Q_INVOKABLE void         deleteMedia(int mediaId);

  signals:
    void albumsChanged();
    void scanningChanged(bool scanning);
    void scanComplete(int photoCount, int videoCount);
    void newMediaAdded(const QString &path);
    void libraryChanged();
    void scanProgressChanged(int progress);

  private slots:
    void onDirectoryChanged(const QString &path);
    void performScan();
    void onScanFinished(QList<MediaItem> items);
    void onScanProgress(int current, int total);

  private:
    void                     initDatabase();
    void                     scanDirectory(const QString &path);
    void                     addMediaItem(const QString &filePath);
    void                     addMediaItemBatch(const QList<MediaItem> &items); // Batch insert
    void                     extractPhotoMetadata(const QString &path, MediaItem &item);
    QString                  createThumbnail(const QString &sourcePath);
    void                     loadAlbums();
    QString                  getAlbumForPath(const QString &path);
    QString                  getThumbnailsDir();
    QString                  getCacheDir();
    bool                     isImageFile(const QString &path);
    bool                     isVideoFile(const QString &path);
    QStringList              getScanPaths();

    QList<Album>             m_albums;
    QSqlDatabase             m_database;
    QFileSystemWatcher      *m_watcher;
    QTimer                  *m_scanTimer;
    QThread                 *m_scanThread;
    MediaScanWorker         *m_scanWorker;
    bool                     m_isScanning;
    int                      m_photoCount;
    int                      m_videoCount;
    int                      m_scanProgress;
    QMutex                   m_mutex;

    static const QStringList IMAGE_EXTENSIONS;
    static const QStringList VIDEO_EXTENSIONS;
};

#endif // MEDIALIBRARYMANAGER_H
