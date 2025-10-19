#ifndef MUSICLIBRARYMANAGER_H
#define MUSICLIBRARYMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QFileSystemWatcher>
#include <QTimer>

struct Track {
    int id;
    QString path;
    QString title;
    QString artist;
    QString album;
    int duration;
    int trackNumber;
    QString year;
};

struct Artist {
    QString name;
    int albumCount;
    int trackCount;
};

class MusicLibraryManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList artists READ artists NOTIFY libraryChanged)
    Q_PROPERTY(bool isScanning READ isScanning NOTIFY scanningChanged)
    Q_PROPERTY(int trackCount READ trackCount NOTIFY libraryChanged)

public:
    explicit MusicLibraryManager(QObject *parent = nullptr);
    ~MusicLibraryManager();

    QVariantList artists() const;
    bool isScanning() const;
    int trackCount() const;

    Q_INVOKABLE void scanLibrary();
    Q_INVOKABLE QVariantList getAlbums(const QString& artistName);
    Q_INVOKABLE QVariantList getTracks(const QString& albumName);
    Q_INVOKABLE QVariantList getAllTracks();
    Q_INVOKABLE QVariantMap getTrackMetadata(int trackId);

signals:
    void libraryChanged();
    void scanningChanged(bool scanning);
    void scanComplete(int trackCount);

private slots:
    void onDirectoryChanged(const QString& path);
    void performScan();

private:
    void initDatabase();
    void scanDirectory(const QString& path);
    void addTrack(const QString& filePath);
    void extractMetadata(const QString& path, Track& track);
    void loadArtists();
    bool isAudioFile(const QString& path);
    
    QList<Artist> m_artists;
    QSqlDatabase m_database;
    QFileSystemWatcher* m_watcher;
    QTimer* m_scanTimer;
    bool m_isScanning;
    int m_trackCount;
    
    static const QStringList AUDIO_EXTENSIONS;
};

#endif // MUSICLIBRARYMANAGER_H

