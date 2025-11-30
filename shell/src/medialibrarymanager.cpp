#include "medialibrarymanager.h"
#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QSqlQuery>
#include <QSqlError>
#include <QImage>
#include <QImageReader>
#include <QFileInfo>
#include <QDateTime>
#include <QDebug>

// Static const for extensions
const QStringList MediaScanWorker::IMAGE_EXTENSIONS = {"jpg", "jpeg", "png",  "gif",
                                                       "bmp", "webp", "heic", "heif"};

const QStringList MediaScanWorker::VIDEO_EXTENSIONS = {"mp4",  "mov", "avi", "mkv",
                                                       "webm", "m4v", "3gp"};

const QStringList MediaLibraryManager::IMAGE_EXTENSIONS = {"jpg", "jpeg", "png",  "gif",
                                                           "bmp", "webp", "heic", "heif"};

const QStringList MediaLibraryManager::VIDEO_EXTENSIONS = {"mp4",  "mov", "avi", "mkv",
                                                           "webm", "m4v", "3gp"};

// ===== MediaScanWorker Implementation =====

MediaScanWorker::MediaScanWorker(const QStringList &paths, QObject *parent)
    : QObject(parent)
    , m_paths(paths) {}

void MediaScanWorker::process() {
    qDebug() << "[MediaScanWorker] Starting scan of" << m_paths.size() << "paths";

    QList<MediaItem> items;
    int              totalFiles  = 0;
    int              currentFile = 0;

    // First pass: count files
    for (const QString &path : m_paths) {
        QDirIterator countIt(path, QDir::Files | QDir::NoDotAndDotDot,
                             QDirIterator::Subdirectories);
        while (countIt.hasNext()) {
            countIt.next();
            totalFiles++;
        }
    }

    qDebug() << "[MediaScanWorker] Found" << totalFiles << "total files to scan";

    // Second pass: scan files
    for (const QString &path : m_paths) {
        QDirIterator it(path, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);

        while (it.hasNext()) {
            QString   filePath = it.next();
            QFileInfo fileInfo(filePath);
            QString   extension = fileInfo.suffix().toLower();

            if (IMAGE_EXTENSIONS.contains(extension) || VIDEO_EXTENSIONS.contains(extension)) {
                MediaItem item = scanFile(filePath);
                if (!item.path.isEmpty()) {
                    items.append(item);
                }

                currentFile++;
                if (currentFile % 50 == 0) { // Emit progress every 50 files
                    emit scanProgress(currentFile, totalFiles);
                }
            }
        }
    }

    qDebug() << "[MediaScanWorker] Scan complete. Found" << items.size() << "media items";
    emit scanProgress(totalFiles, totalFiles); // 100%
    emit scanFinished(items);
}

MediaItem MediaScanWorker::scanFile(const QString &filePath) {
    MediaItem item;
    item.id   = -1; // Will be set by database
    item.path = filePath;

    QFileInfo fileInfo(filePath);
    QString   extension = fileInfo.suffix().toLower();

    item.type      = IMAGE_EXTENSIONS.contains(extension) ? "photo" : "video";
    item.timestamp = fileInfo.lastModified().toMSecsSinceEpoch();
    item.width     = 0;
    item.height    = 0;

    // Extract image dimensions if it's a photo
    if (item.type == "photo") {
        QImageReader reader(filePath);
        if (reader.canRead()) {
            QSize size  = reader.size();
            item.width  = size.width();
            item.height = size.height();
        }
    }

    return item;
}

bool MediaScanWorker::isImageFile(const QString &path) {
    QString extension = QFileInfo(path).suffix().toLower();
    return IMAGE_EXTENSIONS.contains(extension);
}

bool MediaScanWorker::isVideoFile(const QString &path) {
    QString extension = QFileInfo(path).suffix().toLower();
    return VIDEO_EXTENSIONS.contains(extension);
}

// ===== MediaLibraryManager Implementation =====

MediaLibraryManager::MediaLibraryManager(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
    , m_scanTimer(new QTimer(this))
    , m_scanThread(nullptr)
    , m_scanWorker(nullptr)
    , m_isScanning(false)
    , m_photoCount(0)
    , m_videoCount(0)
    , m_scanProgress(0) {
    initDatabase();
    loadAlbums();

    m_scanTimer->setSingleShot(true);
    m_scanTimer->setInterval(2000);
    connect(m_scanTimer, &QTimer::timeout, this, &MediaLibraryManager::performScan);

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this,
            &MediaLibraryManager::onDirectoryChanged);

    QString picturesPath = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (QDir(picturesPath).exists()) {
        m_watcher->addPath(picturesPath);
    }

    qDebug() << "[MediaLibraryManager] Initialized";
}

MediaLibraryManager::~MediaLibraryManager() {
    if (m_database.isOpen()) {
        m_database.close();
    }
}

QVariantList MediaLibraryManager::albums() const {
    QVariantList list;
    for (const Album &album : m_albums) {
        QVariantMap map;
        map["id"]           = album.id;
        map["name"]         = album.name;
        map["photoCount"]   = album.photoCount;
        map["coverPath"]    = album.coverPath;
        map["lastModified"] = album.lastModified;
        list.append(map);
    }
    return list;
}

bool MediaLibraryManager::isScanning() const {
    return m_isScanning;
}

int MediaLibraryManager::photoCount() const {
    return m_photoCount;
}

int MediaLibraryManager::videoCount() const {
    return m_videoCount;
}

int MediaLibraryManager::scanProgress() const {
    return m_scanProgress;
}

QStringList MediaLibraryManager::getScanPaths() {
    QStringList paths;
    QString     picturesPath = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    paths << picturesPath;

#ifndef Q_OS_MACOS
    QString dcimPath = QDir::homePath() + "/DCIM";
    if (QDir(dcimPath).exists()) {
        paths << dcimPath;
    }
#endif

    return paths;
}

void MediaLibraryManager::scanLibrary() {
    // Synchronous version for backwards compatibility
    if (m_isScanning) {
        qDebug() << "[MediaLibraryManager] Scan already in progress";
        return;
    }

    m_isScanning = true;
    emit scanningChanged(true);

    qDebug() << "[MediaLibraryManager] Starting library scan...";

    QString picturesPath = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    QDir    picturesDir(picturesPath);

    if (!picturesDir.exists()) {
        picturesDir.mkpath(picturesPath);
    }

    scanDirectory(picturesPath);

#ifndef Q_OS_MACOS
    QString dcimPath = QDir::homePath() + "/DCIM";
    if (QDir(dcimPath).exists()) {
        scanDirectory(dcimPath);
    }
#endif

    loadAlbums();

    QSqlQuery countQuery(m_database);
    countQuery.exec("SELECT COUNT(*) FROM media WHERE type='photo'");
    if (countQuery.next()) {
        m_photoCount = countQuery.value(0).toInt();
    }

    countQuery.exec("SELECT COUNT(*) FROM media WHERE type='video'");
    if (countQuery.next()) {
        m_videoCount = countQuery.value(0).toInt();
    }

    m_isScanning = false;
    emit scanningChanged(false);
    emit scanComplete(m_photoCount, m_videoCount);
    emit libraryChanged();

    qDebug() << "[MediaLibraryManager] Scan complete:" << m_photoCount << "photos," << m_videoCount
             << "videos";
}

void MediaLibraryManager::scanLibraryAsync() {
    qDebug() << "[MediaLibraryManager] Starting ASYNC library scan...";

    if (m_isScanning) {
        qDebug() << "[MediaLibraryManager] Scan already in progress";
        return;
    }

    // Clean up previous thread if exists
    if (m_scanThread) {
        m_scanThread->quit();
        m_scanThread->wait();
        delete m_scanThread;
        m_scanThread = nullptr;
    }

    m_isScanning   = true;
    m_scanProgress = 0;
    emit scanningChanged(true);
    emit scanProgressChanged(0);

    // Create worker and thread
    QStringList paths = getScanPaths();
    m_scanWorker      = new MediaScanWorker(paths);
    m_scanThread      = new QThread();
    m_scanWorker->moveToThread(m_scanThread);

    // Connect signals
    connect(m_scanThread, &QThread::started, m_scanWorker, &MediaScanWorker::process);
    connect(m_scanWorker, &MediaScanWorker::scanProgress, this,
            &MediaLibraryManager::onScanProgress);
    connect(m_scanWorker, &MediaScanWorker::scanFinished, this,
            &MediaLibraryManager::onScanFinished);
    connect(m_scanWorker, &MediaScanWorker::scanError, this, [this](const QString &error) {
        qWarning() << "[MediaLibraryManager] Scan error:" << error;
        m_isScanning = false;
        emit scanningChanged(false);
    });

    // Clean up thread when done
    connect(m_scanWorker, &MediaScanWorker::scanFinished, m_scanThread, &QThread::quit);
    connect(m_scanThread, &QThread::finished, m_scanWorker, &QObject::deleteLater);
    connect(m_scanThread, &QThread::finished, m_scanThread, &QObject::deleteLater);

    // Start scanning
    m_scanThread->start();
}

void MediaLibraryManager::onScanProgress(int current, int total) {
    if (total > 0) {
        m_scanProgress = (current * 100) / total;
        emit scanProgressChanged(m_scanProgress);
    }
}

void MediaLibraryManager::onScanFinished(QList<MediaItem> items) {
    qDebug() << "[MediaLibraryManager] Async scan finished. Processing" << items.size() << "items";

    // Batch insert all items
    addMediaItemBatch(items);

    // Update counts and albums
    loadAlbums();

    QSqlQuery countQuery(m_database);
    countQuery.exec("SELECT COUNT(*) FROM media WHERE type='photo'");
    if (countQuery.next()) {
        m_photoCount = countQuery.value(0).toInt();
    }

    countQuery.exec("SELECT COUNT(*) FROM media WHERE type='video'");
    if (countQuery.next()) {
        m_videoCount = countQuery.value(0).toInt();
    }

    m_isScanning   = false;
    m_scanProgress = 100;
    emit scanningChanged(false);
    emit scanProgressChanged(100);
    emit scanComplete(m_photoCount, m_videoCount);
    emit libraryChanged();

    qDebug() << "[MediaLibraryManager] Async scan complete:" << m_photoCount << "photos,"
             << m_videoCount << "videos";
}

void MediaLibraryManager::addMediaItemBatch(const QList<MediaItem> &items) {
    if (items.isEmpty())
        return;

    qDebug() << "[MediaLibraryManager] Batch inserting" << items.size() << "media items";

    m_database.transaction();

    QSqlQuery query(m_database);
    query.prepare("INSERT OR REPLACE INTO media (path, type, album, timestamp, width, height) "
                  "VALUES (:path, :type, :album, :timestamp, :width, :height)");

    for (const MediaItem &item : items) {
        QString album = getAlbumForPath(item.path);

        query.bindValue(":path", item.path);
        query.bindValue(":type", item.type);
        query.bindValue(":album", album);
        query.bindValue(":timestamp", item.timestamp);
        query.bindValue(":width", item.width);
        query.bindValue(":height", item.height);

        if (!query.exec()) {
            qWarning() << "[MediaLibraryManager] Failed to insert:" << query.lastError().text();
        }
    }

    m_database.commit();
    qDebug() << "[MediaLibraryManager] Batch insert complete";
}

QVariantList MediaLibraryManager::getPhotos(const QString &albumId) {
    QVariantList list;

    QSqlQuery    query(m_database);
    query.prepare("SELECT id, path, thumbnail_path, width, height, timestamp FROM media WHERE "
                  "album = ? AND type = 'photo' ORDER BY timestamp DESC");
    query.addBindValue(albumId);

    if (query.exec()) {
        while (query.next()) {
            QVariantMap map;
            map["id"]   = query.value(0).toInt();
            map["path"] = "file://" + query.value(1).toString();
            map["thumbnailPath"] =
                query.value(2).toString().isEmpty() ? "" : "file://" + query.value(2).toString();
            map["width"]     = query.value(3).toInt();
            map["height"]    = query.value(4).toInt();
            map["timestamp"] = query.value(5).toLongLong();
            list.append(map);
        }
    }

    return list;
}

QVariantList MediaLibraryManager::getVideos() {
    QVariantList list;

    QSqlQuery    query(m_database);
    query.exec("SELECT id, path, thumbnail_path, timestamp FROM media WHERE type = 'video' ORDER "
               "BY timestamp DESC");

    while (query.next()) {
        QVariantMap map;
        map["id"]   = query.value(0).toInt();
        map["path"] = "file://" + query.value(1).toString();
        map["thumbnailPath"] =
            query.value(2).toString().isEmpty() ? "" : "file://" + query.value(2).toString();
        map["timestamp"] = query.value(3).toLongLong();
        list.append(map);
    }

    return list;
}

QVariantList MediaLibraryManager::getAllPhotos() {
    QVariantList list;

    QSqlQuery    query(m_database);
    query.exec("SELECT id, path, thumbnail_path, width, height, timestamp, album FROM media WHERE "
               "type = 'photo' ORDER BY timestamp DESC");

    while (query.next()) {
        QVariantMap map;
        map["id"]   = query.value(0).toInt();
        map["path"] = "file://" + query.value(1).toString();
        map["thumbnailPath"] =
            query.value(2).toString().isEmpty() ? "" : "file://" + query.value(2).toString();
        map["width"]     = query.value(3).toInt();
        map["height"]    = query.value(4).toInt();
        map["timestamp"] = query.value(5).toLongLong();
        map["album"]     = query.value(6).toString();
        list.append(map);
    }

    return list;
}

QString MediaLibraryManager::generateThumbnail(const QString &filePath) {
    QString cleanPath = filePath;
    if (cleanPath.startsWith("file://")) {
        cleanPath = cleanPath.mid(7);
    }

    return createThumbnail(cleanPath);
}

void MediaLibraryManager::deleteMedia(int mediaId) {
    QSqlQuery query(m_database);
    query.prepare("SELECT path, thumbnail_path FROM media WHERE id = ?");
    query.addBindValue(mediaId);

    if (query.exec() && query.next()) {
        QString filePath  = query.value(0).toString();
        QString thumbPath = query.value(1).toString();

        QFile::remove(filePath);
        if (!thumbPath.isEmpty()) {
            QFile::remove(thumbPath);
        }

        QSqlQuery deleteQuery(m_database);
        deleteQuery.prepare("DELETE FROM media WHERE id = ?");
        deleteQuery.addBindValue(mediaId);
        deleteQuery.exec();

        loadAlbums();
        emit libraryChanged();

        qDebug() << "[MediaLibraryManager] Deleted media:" << mediaId;
    }
}

void MediaLibraryManager::onDirectoryChanged(const QString &path) {
    qDebug() << "[MediaLibraryManager] Directory changed:" << path;
    m_scanTimer->start();
}

void MediaLibraryManager::performScan() {
    scanLibrary();
}

void MediaLibraryManager::initDatabase() {
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QString dbPath  = dataDir + "/marathon";

    QDir    dir;
    if (!dir.exists(dbPath)) {
        dir.mkpath(dbPath);
    }

    m_database = QSqlDatabase::addDatabase("QSQLITE", "medialibrary");
    m_database.setDatabaseName(dbPath + "/medialibrary.db");

    if (!m_database.open()) {
        qWarning() << "[MediaLibraryManager] Failed to open database:"
                   << m_database.lastError().text();
        return;
    }

    QSqlQuery query(m_database);
    bool      success = query.exec("CREATE TABLE IF NOT EXISTS media ("
                                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                                        "path TEXT NOT NULL UNIQUE, "
                                        "type TEXT NOT NULL, "
                                        "album TEXT, "
                                        "timestamp INTEGER NOT NULL, "
                                        "width INTEGER DEFAULT 0, "
                                        "height INTEGER DEFAULT 0, "
                                        "thumbnail_path TEXT)");

    if (!success) {
        qWarning() << "[MediaLibraryManager] Failed to create table:" << query.lastError().text();
    }

    qDebug() << "[MediaLibraryManager] Database initialized at" << dbPath;
}

void MediaLibraryManager::scanDirectory(const QString &path) {
    QDirIterator it(path, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);

    while (it.hasNext()) {
        QString   filePath = it.next();
        QFileInfo fileInfo(filePath);
        QString   extension = fileInfo.suffix().toLower();

        if (IMAGE_EXTENSIONS.contains(extension) || VIDEO_EXTENSIONS.contains(extension)) {
            addMediaItem(filePath);
        }
    }
}

void MediaLibraryManager::addMediaItem(const QString &filePath) {
    QFileInfo fileInfo(filePath);
    if (!fileInfo.exists()) {
        return;
    }

    QSqlQuery checkQuery(m_database);
    checkQuery.prepare("SELECT id FROM media WHERE path = ?");
    checkQuery.addBindValue(filePath);

    if (checkQuery.exec() && checkQuery.next()) {
        return;
    }

    MediaItem item;
    item.path      = filePath;
    item.timestamp = fileInfo.lastModified().toMSecsSinceEpoch();
    item.album     = getAlbumForPath(filePath);

    QString extension = fileInfo.suffix().toLower();

    if (IMAGE_EXTENSIONS.contains(extension)) {
        item.type = "photo";
        extractPhotoMetadata(filePath, item);
        item.thumbnailPath = createThumbnail(filePath);
    } else if (VIDEO_EXTENSIONS.contains(extension)) {
        item.type          = "video";
        item.width         = 0;
        item.height        = 0;
        item.thumbnailPath = "";
    }

    QSqlQuery insertQuery(m_database);
    insertQuery.prepare("INSERT INTO media (path, type, album, timestamp, width, height, "
                        "thumbnail_path) VALUES (?, ?, ?, ?, ?, ?, ?)");
    insertQuery.addBindValue(item.path);
    insertQuery.addBindValue(item.type);
    insertQuery.addBindValue(item.album);
    insertQuery.addBindValue(item.timestamp);
    insertQuery.addBindValue(item.width);
    insertQuery.addBindValue(item.height);
    insertQuery.addBindValue(item.thumbnailPath);

    if (insertQuery.exec()) {
        emit newMediaAdded(filePath);
    }
}

void MediaLibraryManager::extractPhotoMetadata(const QString &path, MediaItem &item) {
    QImageReader reader(path);
    if (reader.canRead()) {
        QSize size  = reader.size();
        item.width  = size.width();
        item.height = size.height();
    } else {
        item.width  = 0;
        item.height = 0;
    }
}

QString MediaLibraryManager::createThumbnail(const QString &sourcePath) {
    QFileInfo sourceInfo(sourcePath);
    QString   thumbnailsDir = getThumbnailsDir();
    QString   thumbFileName = sourceInfo.fileName() + "_thumb.jpg";
    QString   thumbPath     = thumbnailsDir + "/" + thumbFileName;

    if (QFile::exists(thumbPath)) {
        return thumbPath;
    }

    QImage image(sourcePath);
    if (image.isNull()) {
        return QString();
    }

    QImage thumbnail = image.scaled(256, 256, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    if (thumbnail.save(thumbPath, "JPG", 85)) {
        return thumbPath;
    }

    return QString();
}

void MediaLibraryManager::loadAlbums() {
    m_albums.clear();

    QSqlQuery query(m_database);
    query.exec("SELECT album, COUNT(*) as photo_count, MIN(path) as cover_path, MAX(timestamp) as "
               "last_modified "
               "FROM media "
               "WHERE type = 'photo' "
               "GROUP BY album "
               "ORDER BY last_modified DESC");

    while (query.next()) {
        Album album;
        album.id           = query.value(0).toString();
        album.name         = album.id.isEmpty() ? "All Photos" : album.id;
        album.photoCount   = query.value(1).toInt();
        album.coverPath    = query.value(2).toString();
        album.lastModified = query.value(3).toLongLong();

        m_albums.append(album);
    }

    emit albumsChanged();
}

QString MediaLibraryManager::getAlbumForPath(const QString &path) {
    QFileInfo fileInfo(path);
    QString   parentDirName = fileInfo.dir().dirName();

    if (parentDirName.isEmpty() || parentDirName == "Pictures" || parentDirName == "DCIM") {
        return "Camera Roll";
    }

    return parentDirName;
}

QString MediaLibraryManager::getThumbnailsDir() {
    QString cacheDir      = getCacheDir();
    QString thumbnailsDir = cacheDir + "/thumbnails";

    QDir    dir;
    if (!dir.exists(thumbnailsDir)) {
        dir.mkpath(thumbnailsDir);
    }

    return thumbnailsDir;
}

QString MediaLibraryManager::getCacheDir() {
    QString cacheDir      = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QString marathonCache = cacheDir + "/marathon";

    QDir    dir;
    if (!dir.exists(marathonCache)) {
        dir.mkpath(marathonCache);
    }

    return marathonCache;
}

bool MediaLibraryManager::isImageFile(const QString &path) {
    QFileInfo fileInfo(path);
    return IMAGE_EXTENSIONS.contains(fileInfo.suffix().toLower());
}

bool MediaLibraryManager::isVideoFile(const QString &path) {
    QFileInfo fileInfo(path);
    return VIDEO_EXTENSIONS.contains(fileInfo.suffix().toLower());
}
