#include "musiclibrarymanager.h"
#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QSqlQuery>
#include <QSqlError>
#include <QFileInfo>
#include <QDebug>
#include <QMediaPlayer>
#include <QAudioOutput>

// Static const for extensions
const QStringList MusicScanWorker::AUDIO_EXTENSIONS = {"mp3",  "m4a", "flac", "ogg",
                                                       "opus", "wav", "aac",  "wma"};

const QStringList MusicLibraryManager::AUDIO_EXTENSIONS = {"mp3",  "m4a", "flac", "ogg",
                                                           "opus", "wav", "aac",  "wma"};

// ===== MusicScanWorker Implementation =====

MusicScanWorker::MusicScanWorker(const QStringList &paths, QObject *parent)
    : QObject(parent)
    , m_paths(paths) {}

void MusicScanWorker::process() {
    qDebug() << "[MusicScanWorker] Starting scan of" << m_paths.size() << "paths";

    QList<Track> tracks;
    int          totalFiles  = 0;
    int          currentFile = 0;

    // First pass: count files
    for (const QString &path : m_paths) {
        QDirIterator countIt(path, QDir::Files | QDir::NoDotAndDotDot,
                             QDirIterator::Subdirectories);
        while (countIt.hasNext()) {
            countIt.next();
            totalFiles++;
        }
    }

    qDebug() << "[MusicScanWorker] Found" << totalFiles << "total files to scan";

    // Second pass: scan files
    for (const QString &path : m_paths) {
        QDirIterator it(path, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);

        while (it.hasNext()) {
            QString   filePath = it.next();
            QFileInfo fileInfo(filePath);
            QString   extension = fileInfo.suffix().toLower();

            if (AUDIO_EXTENSIONS.contains(extension)) {
                Track track = scanFile(filePath);
                if (!track.path.isEmpty()) {
                    tracks.append(track);
                }

                currentFile++;
                if (currentFile % 50 == 0) { // Emit progress every 50 files
                    emit scanProgress(currentFile, totalFiles);
                }
            }
        }
    }

    qDebug() << "[MusicScanWorker] Scan complete. Found" << tracks.size() << "music tracks";
    emit scanProgress(totalFiles, totalFiles); // 100%
    emit scanFinished(tracks);
}

Track MusicScanWorker::scanFile(const QString &filePath) {
    Track track;
    track.id   = -1; // Will be set by database
    track.path = filePath;

    QFileInfo fileInfo(filePath);

    // Basic metadata from filename/path
    track.title       = fileInfo.completeBaseName();
    track.artist      = "Unknown Artist";
    track.album       = "Unknown Album";
    track.duration    = 0;
    track.trackNumber = 0;
    track.year        = "";

    // Try to extract from path structure: .../Artist/Album/Track.mp3
    QStringList pathParts = fileInfo.absolutePath().split('/');
    if (pathParts.size() >= 2) {
        track.album  = pathParts[pathParts.size() - 1];
        track.artist = pathParts[pathParts.size() - 2];
    }

    return track;
}

bool MusicScanWorker::isAudioFile(const QString &path) {
    QString extension = QFileInfo(path).suffix().toLower();
    return AUDIO_EXTENSIONS.contains(extension);
}

// ===== MusicLibraryManager Implementation =====

MusicLibraryManager::MusicLibraryManager(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
    , m_scanTimer(new QTimer(this))
    , m_scanThread(nullptr)
    , m_scanWorker(nullptr)
    , m_isScanning(false)
    , m_trackCount(0)
    , m_scanProgress(0) {
    initDatabase();
    loadArtists();

    m_scanTimer->setSingleShot(true);
    m_scanTimer->setInterval(2000);
    connect(m_scanTimer, &QTimer::timeout, this, &MusicLibraryManager::performScan);

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this,
            &MusicLibraryManager::onDirectoryChanged);

    QString musicPath = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (QDir(musicPath).exists()) {
        m_watcher->addPath(musicPath);
    }

    qDebug() << "[MusicLibraryManager] Initialized";
}

MusicLibraryManager::~MusicLibraryManager() {
    if (m_database.isOpen()) {
        m_database.close();
    }
}

QVariantList MusicLibraryManager::artists() const {
    QVariantList list;
    for (const Artist &artist : m_artists) {
        QVariantMap map;
        map["name"]       = artist.name;
        map["albumCount"] = artist.albumCount;
        map["trackCount"] = artist.trackCount;
        list.append(map);
    }
    return list;
}

bool MusicLibraryManager::isScanning() const {
    return m_isScanning;
}

int MusicLibraryManager::trackCount() const {
    return m_trackCount;
}

void MusicLibraryManager::scanLibrary() {
    if (m_isScanning) {
        qDebug() << "[MusicLibraryManager] Scan already in progress";
        return;
    }

    m_isScanning = true;
    emit scanningChanged(true);

    qDebug() << "[MusicLibraryManager] Starting library scan...";

    QString musicPath = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    QDir    musicDir(musicPath);

    if (!musicDir.exists()) {
        musicDir.mkpath(musicPath);
    }

    scanDirectory(musicPath);

    loadArtists();

    QSqlQuery countQuery(m_database);
    countQuery.exec("SELECT COUNT(*) FROM tracks");
    if (countQuery.next()) {
        m_trackCount = countQuery.value(0).toInt();
    }

    m_isScanning = false;
    emit scanningChanged(false);
    emit scanComplete(m_trackCount);
    emit libraryChanged();

    qDebug() << "[MusicLibraryManager] Scan complete:" << m_trackCount << "tracks";
}

void MusicLibraryManager::scanLibraryAsync() {
    if (m_isScanning) {
        qDebug() << "[MusicLibraryManager] Async scan already in progress";
        return;
    }

    m_isScanning   = true;
    m_scanProgress = 0;
    emit scanningChanged(true);
    emit scanProgressChanged(0);

    qDebug() << "[MusicLibraryManager] Starting async library scan...";

    // Create worker and thread
    m_scanWorker = new MusicScanWorker(getScanPaths());
    m_scanThread = new QThread();

    m_scanWorker->moveToThread(m_scanThread);

    // Connect signals
    connect(m_scanThread, &QThread::started, m_scanWorker, &MusicScanWorker::process);
    connect(m_scanWorker, &MusicScanWorker::scanProgress, this,
            &MusicLibraryManager::onScanProgress);
    connect(m_scanWorker, &MusicScanWorker::scanFinished, this,
            &MusicLibraryManager::onScanFinished);
    connect(m_scanWorker, &MusicScanWorker::scanError, this, [this](const QString &error) {
        qWarning() << "[MusicLibraryManager] Scan error:" << error;
        m_isScanning = false;
        emit scanningChanged(false);
    });

    // Cleanup when done
    connect(m_scanWorker, &MusicScanWorker::scanFinished, m_scanThread, &QThread::quit);
    connect(m_scanThread, &QThread::finished, m_scanWorker, &QObject::deleteLater);
    connect(m_scanThread, &QThread::finished, m_scanThread, &QObject::deleteLater);
    connect(m_scanThread, &QThread::finished, this, [this]() {
        m_scanThread = nullptr;
        m_scanWorker = nullptr;
    });

    // Start the scan
    m_scanThread->start();
}

int MusicLibraryManager::scanProgress() const {
    QMutexLocker locker(&m_mutex);
    return m_scanProgress;
}

void MusicLibraryManager::onScanProgress(int current, int total) {
    {
        QMutexLocker locker(&m_mutex);
        m_scanProgress = (total > 0) ? (current * 100 / total) : 0;
    }
    emit scanProgressChanged(m_scanProgress);
}

void MusicLibraryManager::onScanFinished(QList<Track> tracks) {
    qDebug() << "[MusicLibraryManager] Async scan finished. Processing" << tracks.size()
             << "tracks";

    // Add all tracks to database in a batch
    addTrackBatch(tracks);

    // Update counts
    QSqlQuery countQuery(m_database);
    countQuery.exec("SELECT COUNT(*) FROM tracks");
    if (countQuery.next()) {
        m_trackCount = countQuery.value(0).toInt();
    }

    // Reload artists
    loadArtists();

    m_isScanning = false;
    emit scanningChanged(false);
    emit scanComplete(m_trackCount);
    emit libraryChanged();

    qDebug() << "[MusicLibraryManager] Async scan complete:" << m_trackCount << "total tracks";
}

void MusicLibraryManager::addTrackBatch(const QList<Track> &tracks) {
    if (tracks.isEmpty()) {
        return;
    }

    m_database.transaction();

    QSqlQuery query(m_database);
    query.prepare(
        "INSERT OR REPLACE INTO tracks (path, title, artist, album, duration, track_number, year) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)");

    for (const Track &track : tracks) {
        query.addBindValue(track.path);
        query.addBindValue(track.title);
        query.addBindValue(track.artist);
        query.addBindValue(track.album);
        query.addBindValue(track.duration);
        query.addBindValue(track.trackNumber);
        query.addBindValue(track.year);

        if (!query.exec()) {
            qWarning() << "[MusicLibraryManager] Failed to insert track:"
                       << query.lastError().text();
        }
    }

    m_database.commit();
    qDebug() << "[MusicLibraryManager] Batch inserted" << tracks.size() << "tracks";
}

QStringList MusicLibraryManager::getScanPaths() {
    QStringList paths;

    QString     musicPath = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    QDir        musicDir(musicPath);

    if (!musicDir.exists()) {
        musicDir.mkpath(musicPath);
    }

    paths << musicPath;

    // Could add additional paths here (e.g., SD card, custom music folders)

    return paths;
}

QVariantList MusicLibraryManager::getAlbums(const QString &artistName) {
    QVariantList list;

    QSqlQuery    query(m_database);
    query.prepare("SELECT DISTINCT album, COUNT(*) as track_count FROM tracks WHERE artist = ? "
                  "GROUP BY album ORDER BY album");
    query.addBindValue(artistName);

    if (query.exec()) {
        while (query.next()) {
            QVariantMap map;
            map["name"]       = query.value(0).toString();
            map["trackCount"] = query.value(1).toInt();
            map["artist"]     = artistName;
            list.append(map);
        }
    }

    return list;
}

QVariantList MusicLibraryManager::getTracks(const QString &albumName) {
    QVariantList list;

    QSqlQuery    query(m_database);
    query.prepare("SELECT id, path, title, artist, album, duration, track_number FROM tracks WHERE "
                  "album = ? ORDER BY track_number, title");
    query.addBindValue(albumName);

    if (query.exec()) {
        while (query.next()) {
            QVariantMap map;
            map["id"]          = query.value(0).toInt();
            map["path"]        = "file://" + query.value(1).toString();
            map["title"]       = query.value(2).toString();
            map["artist"]      = query.value(3).toString();
            map["album"]       = query.value(4).toString();
            map["duration"]    = query.value(5).toInt();
            map["trackNumber"] = query.value(6).toInt();
            list.append(map);
        }
    }

    return list;
}

QVariantList MusicLibraryManager::getAllTracks() {
    QVariantList list;

    QSqlQuery    query(m_database);
    query.exec("SELECT id, path, title, artist, album, duration, track_number FROM tracks ORDER BY "
               "artist, album, track_number");

    while (query.next()) {
        QVariantMap map;
        map["id"]          = query.value(0).toInt();
        map["path"]        = "file://" + query.value(1).toString();
        map["title"]       = query.value(2).toString();
        map["artist"]      = query.value(3).toString();
        map["album"]       = query.value(4).toString();
        map["duration"]    = query.value(5).toInt();
        map["trackNumber"] = query.value(6).toInt();
        list.append(map);
    }

    return list;
}

QVariantMap MusicLibraryManager::getTrackMetadata(int trackId) {
    QVariantMap map;

    QSqlQuery   query(m_database);
    query.prepare("SELECT id, path, title, artist, album, duration, track_number, year FROM tracks "
                  "WHERE id = ?");
    query.addBindValue(trackId);

    if (query.exec() && query.next()) {
        map["id"]          = query.value(0).toInt();
        map["path"]        = "file://" + query.value(1).toString();
        map["title"]       = query.value(2).toString();
        map["artist"]      = query.value(3).toString();
        map["album"]       = query.value(4).toString();
        map["duration"]    = query.value(5).toInt();
        map["trackNumber"] = query.value(6).toInt();
        map["year"]        = query.value(7).toString();
    }

    return map;
}

void MusicLibraryManager::onDirectoryChanged(const QString &path) {
    qDebug() << "[MusicLibraryManager] Directory changed:" << path;
    m_scanTimer->start();
}

void MusicLibraryManager::performScan() {
    scanLibrary();
}

void MusicLibraryManager::initDatabase() {
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QString dbPath  = dataDir + "/marathon";

    QDir    dir;
    if (!dir.exists(dbPath)) {
        dir.mkpath(dbPath);
    }

    m_database = QSqlDatabase::addDatabase("QSQLITE", "musiclibrary");
    m_database.setDatabaseName(dbPath + "/musiclibrary.db");

    if (!m_database.open()) {
        qWarning() << "[MusicLibraryManager] Failed to open database:"
                   << m_database.lastError().text();
        return;
    }

    QSqlQuery query(m_database);
    bool      success = query.exec("CREATE TABLE IF NOT EXISTS tracks ("
                                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                                        "path TEXT NOT NULL UNIQUE, "
                                        "title TEXT, "
                                        "artist TEXT, "
                                        "album TEXT, "
                                        "duration INTEGER DEFAULT 0, "
                                        "track_number INTEGER DEFAULT 0, "
                                        "year TEXT)");

    if (!success) {
        qWarning() << "[MusicLibraryManager] Failed to create table:" << query.lastError().text();
    }

    qDebug() << "[MusicLibraryManager] Database initialized at" << dbPath;
}

void MusicLibraryManager::scanDirectory(const QString &path) {
    QDirIterator it(path, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);

    while (it.hasNext()) {
        QString filePath = it.next();
        if (isAudioFile(filePath)) {
            addTrack(filePath);
        }
    }
}

void MusicLibraryManager::addTrack(const QString &filePath) {
    QFileInfo fileInfo(filePath);
    if (!fileInfo.exists()) {
        return;
    }

    QSqlQuery checkQuery(m_database);
    checkQuery.prepare("SELECT id FROM tracks WHERE path = ?");
    checkQuery.addBindValue(filePath);

    if (checkQuery.exec() && checkQuery.next()) {
        return;
    }

    Track track;
    track.path = filePath;
    extractMetadata(filePath, track);

    QSqlQuery insertQuery(m_database);
    insertQuery.prepare("INSERT INTO tracks (path, title, artist, album, duration, track_number, "
                        "year) VALUES (?, ?, ?, ?, ?, ?, ?)");
    insertQuery.addBindValue(track.path);
    insertQuery.addBindValue(track.title);
    insertQuery.addBindValue(track.artist);
    insertQuery.addBindValue(track.album);
    insertQuery.addBindValue(track.duration);
    insertQuery.addBindValue(track.trackNumber);
    insertQuery.addBindValue(track.year);

    if (!insertQuery.exec()) {
        qWarning() << "[MusicLibraryManager] Failed to insert track:"
                   << insertQuery.lastError().text();
    }
}

void MusicLibraryManager::extractMetadata(const QString &path, Track &track) {
    QFileInfo fileInfo(path);

    track.title       = fileInfo.completeBaseName();
    track.artist      = "Unknown Artist";
    track.album       = "Unknown Album";
    track.duration    = 0;
    track.trackNumber = 0;
    track.year        = "";

    QString dirName = fileInfo.dir().dirName();
    if (!dirName.isEmpty() && dirName != "Music") {
        track.album = dirName;
    }

    QStringList parts = track.title.split(" - ");
    if (parts.size() >= 2) {
        track.artist = parts[0].trimmed();
        track.title  = parts[1].trimmed();
    }
}

void MusicLibraryManager::loadArtists() {
    m_artists.clear();

    QSqlQuery query(m_database);
    query.exec("SELECT artist, COUNT(DISTINCT album) as album_count, COUNT(*) as track_count "
               "FROM tracks "
               "GROUP BY artist "
               "ORDER BY artist");

    while (query.next()) {
        Artist artist;
        artist.name       = query.value(0).toString();
        artist.albumCount = query.value(1).toInt();
        artist.trackCount = query.value(2).toInt();

        m_artists.append(artist);
    }

    emit libraryChanged();
}

bool MusicLibraryManager::isAudioFile(const QString &path) {
    QFileInfo fileInfo(path);
    return AUDIO_EXTENSIONS.contains(fileInfo.suffix().toLower());
}
