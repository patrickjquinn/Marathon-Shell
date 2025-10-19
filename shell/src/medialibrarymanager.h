#ifndef MEDIALIBRARYMANAGER_H
#define MEDIALIBRARYMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QFileSystemWatcher>
#include <QTimer>

struct MediaItem {
    int id;
    QString path;
    QString type;
    QString album;
    qint64 timestamp;
    int width;
    int height;
    QString thumbnailPath;
};

struct Album {
    QString id;
    QString name;
    int photoCount;
    QString coverPath;
    qint64 lastModified;
};

class MediaLibraryManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList albums READ albums NOTIFY albumsChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int photoCount READ photoCount NOTIFY libraryChanged)
    Q_PROPERTY(int videoCount READ videoCount NOTIFY libraryChanged)

public:
    explicit MediaLibraryManager(QObject *parent = nullptr);
    ~MediaLibraryManager();

    QVariantList albums() const;
    bool isScanning() const;
    int photoCount() const;
    int videoCount() const;

    Q_INVOKABLE void scanLibrary();
    Q_INVOKABLE QVariantList getPhotos(const QString& albumId);
    Q_INVOKABLE QVariantList getVideos();
    Q_INVOKABLE QVariantList getAllPhotos();
    Q_INVOKABLE QString generateThumbnail(const QString& filePath);
    Q_INVOKABLE void deleteMedia(int mediaId);

signals:
    void albumsChanged();
    void scanningChanged(bool scanning);
    void scanComplete(int photoCount, int videoCount);
    void newMediaAdded(const QString& path);
    void libraryChanged();

private slots:
    void onDirectoryChanged(const QString& path);
    void performScan();

private:
    void initDatabase();
    void scanDirectory(const QString& path);
    void addMediaItem(const QString& filePath);
    void extractPhotoMetadata(const QString& path, MediaItem& item);
    QString createThumbnail(const QString& sourcePath);
    void loadAlbums();
    QString getAlbumForPath(const QString& path);
    QString getThumbnailsDir();
    QString getCacheDir();
    bool isImageFile(const QString& path);
    bool isVideoFile(const QString& path);
    
    QList<Album> m_albums;
    QSqlDatabase m_database;
    QFileSystemWatcher* m_watcher;
    QTimer* m_scanTimer;
    bool m_isScanning;
    int m_photoCount;
    int m_videoCount;
    
    static const QStringList IMAGE_EXTENSIONS;
    static const QStringList VIDEO_EXTENSIONS;
};

#endif // MEDIALIBRARYMANAGER_H

