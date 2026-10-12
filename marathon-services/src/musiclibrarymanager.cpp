#include "musiclibrarymanager.h"
#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QFileInfo>
#include <QSet>
#include <QThreadPool>
#include <QAtomicInt>
#include <QDebug>

namespace {
    const QStringList &musicAudioExtensions() {
        static const QStringList list{"mp3", "m4a", "flac", "ogg", "opus", "wav", "aac", "wma"};
        return list;
    }

    constexpr int kBatchSize = 200;

    // Opens a connection for the calling thread; remove it with closeConnection().
    QSqlDatabase openConnection(const QString &dbPath, const QString &prefix) {
        static QAtomicInt counter;
        const QString     name = prefix + QString::number(counter.fetchAndAddRelaxed(1));
        QSqlDatabase      db   = QSqlDatabase::addDatabase("QSQLITE", name);
        db.setDatabaseName(dbPath);
        if (!db.open())
            qWarning() << "[MusicLibraryManager] Failed to open database:" << db.lastError().text();
        return db;
    }

    void closeConnection(QSqlDatabase &db) {
        const QString name = db.connectionName();
        db.close();
        db = QSqlDatabase();
        QSqlDatabase::removeDatabase(name);
    }

    int countTracks(QSqlDatabase &db) {
        QSqlQuery query(db);
        return query.exec("SELECT COUNT(*) FROM tracks") && query.next() ? query.value(0).toInt()
                                                                         : 0;
    }

    QList<Artist> queryArtists(QSqlDatabase &db) {
        QList<Artist> artists;
        QSqlQuery     query(db);
        query.exec("SELECT artist, COUNT(DISTINCT album), COUNT(*) FROM tracks GROUP BY artist "
                   "ORDER BY artist");
        while (query.next())
            artists.append({query.value(0).toString(), query.value(1).toInt(),
                            query.value(2).toInt()});
        return artists;
    }
}

const QStringList &MusicScanWorker::audioExtensions() {
    return musicAudioExtensions();
}

MusicScanWorker::MusicScanWorker(const QStringList &paths, const QString &dbPath, QObject *parent)
    : QObject(parent)
    , m_paths(paths)
    , m_dbPath(dbPath) {}

void MusicScanWorker::process() {
    QStringList files;
    for (const QString &path : std::as_const(m_paths)) {
        QDirIterator it(path, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString filePath = it.next();
            if (audioExtensions().contains(QFileInfo(filePath).suffix().toLower()))
                files.append(filePath);
        }
    }
    const int    total = int(files.size());

    QSqlDatabase  db = openConnection(m_dbPath, "musiclibrary-scan-");
    int           trackCount  = 0;
    bool          interrupted = false;
    QList<Artist> artists;
    {
        QSet<QString> known;
        QSqlQuery     existing(db);
        existing.exec("SELECT path FROM tracks");
        while (existing.next())
            known.insert(existing.value(0).toString());

        QSqlQuery insert(db);
        insert.prepare("INSERT OR IGNORE INTO tracks (path, title, artist, album, duration, "
                       "track_number, year) VALUES (?, ?, ?, ?, ?, ?, ?)");
        int pending = 0;
        db.transaction();
        for (int i = 0; i < total; ++i) {
            if (QThread::currentThread()->isInterruptionRequested()) {
                interrupted = true;
                break;
            }
            const QString &filePath = files.at(i);
            if (!known.remove(filePath)) {
                const Track track = scanFile(filePath);
                insert.addBindValue(track.path);
                insert.addBindValue(track.title);
                insert.addBindValue(track.artist);
                insert.addBindValue(track.album);
                insert.addBindValue(track.duration);
                insert.addBindValue(track.trackNumber);
                insert.addBindValue(track.year);
                if (!insert.exec())
                    qWarning() << "[MusicScanWorker] Failed to insert track:"
                               << insert.lastError().text();
                if (++pending == kBatchSize) {
                    db.commit();
                    emit batchStored(countTracks(db));
                    db.transaction();
                    pending = 0;
                }
            }
            if ((i + 1) % 50 == 0)
                emit scanProgress(i + 1, total);
        }

        // Whatever is still in `known` was deleted or moved since the last scan.
        QSqlQuery remove(db);
        remove.prepare("DELETE FROM tracks WHERE path = ?");
        if (!interrupted) {
            for (const QString &gone : std::as_const(known)) {
                remove.addBindValue(gone);
                remove.exec();
            }
        }
        db.commit();

        trackCount = countTracks(db);
        artists    = queryArtists(db);
    }
    closeConnection(db);
    if (interrupted)
        return;

    emit scanProgress(total, total);
    emit scanFinished(trackCount, artists);
}

Track MusicScanWorker::scanFile(const QString &filePath) {
    Track track;
    track.id   = -1;
    track.path = filePath;

    QFileInfo fileInfo(filePath);

    track.title       = fileInfo.completeBaseName();
    track.artist      = "Unknown Artist";
    track.album       = "Unknown Album";
    track.duration    = 0;
    track.trackNumber = 0;
    track.year        = "";

    QStringList pathParts = fileInfo.absolutePath().split('/');
    if (pathParts.size() >= 2) {
        track.album  = pathParts[pathParts.size() - 1];
        track.artist = pathParts[pathParts.size() - 2];
    }

    return track;
}

MusicLibraryManager::MusicLibraryManager(QObject *parent)
    : QObject(parent)
    , m_watcher(new QFileSystemWatcher(this))
    , m_scanTimer(new QTimer(this))
    , m_scanThread(nullptr)
    , m_scanWorker(nullptr)
    , m_isScanning(false)
    , m_trackCount(0)
    , m_scanProgress(0)
    , m_loadGeneration(0) {
    m_readers.setMaxThreadCount(1);
    initDatabase();

    m_scanTimer->setSingleShot(true);
    m_scanTimer->setInterval(2000);
    connect(m_scanTimer, &QTimer::timeout, this, &MusicLibraryManager::scanLibraryAsync);

    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this,
            &MusicLibraryManager::onDirectoryChanged);

    QString musicPath = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    if (QDir(musicPath).exists()) {
        m_watcher->addPath(musicPath);
    }
}

MusicLibraryManager::~MusicLibraryManager() {
    if (m_scanThread) {
        m_scanThread->requestInterruption();
        m_scanThread->quit();
        m_scanThread->wait();
    }
    m_readers.waitForDone();
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

void MusicLibraryManager::scanLibraryAsync() {
    if (m_isScanning) {
        qDebug() << "[MusicLibraryManager] Async scan already in progress";
        return;
    }

    m_isScanning   = true;
    m_scanProgress = 0;
    emit scanningChanged(true);
    emit scanProgressChanged(0);

    m_scanWorker = new MusicScanWorker(getScanPaths(), m_dbPath);
    m_scanThread = new QThread();

    m_scanWorker->moveToThread(m_scanThread);

    connect(m_scanThread, &QThread::started, m_scanWorker, &MusicScanWorker::process);
    connect(m_scanWorker, &MusicScanWorker::scanProgress, this,
            &MusicLibraryManager::onScanProgress);
    connect(m_scanWorker, &MusicScanWorker::batchStored, this, [this](int trackCount) {
        m_trackCount = trackCount;
        emit libraryChanged();
    });
    connect(m_scanWorker, &MusicScanWorker::scanFinished, this,
            &MusicLibraryManager::onScanFinished);

    connect(m_scanWorker, &MusicScanWorker::scanFinished, m_scanThread, &QThread::quit);
    connect(m_scanThread, &QThread::finished, m_scanWorker, &QObject::deleteLater);
    connect(m_scanThread, &QThread::finished, m_scanThread, &QObject::deleteLater);
    connect(m_scanThread, &QThread::finished, this, [this]() {
        m_scanThread = nullptr;
        m_scanWorker = nullptr;
    });

    m_scanThread->start();
}

void MusicLibraryManager::loadTracksAsync() {
    const int     generation = ++m_loadGeneration;
    const QString dbPath     = m_dbPath;
    m_readers.start([this, generation, dbPath]() {
        QSqlDatabase db = openConnection(dbPath, "musiclibrary-read-");
        QVariantList list;
        {
            QSqlQuery query(db);
            query.exec("SELECT id, path, title, artist, album, duration, track_number FROM tracks "
                       "ORDER BY artist, album, track_number");
            while (query.next()) {
                QVariantMap map;
                map["id"]          = query.value(0).toInt();
                map["path"]        = QString("file://" + query.value(1).toString());
                map["title"]       = query.value(2).toString();
                map["artist"]      = query.value(3).toString();
                map["album"]       = query.value(4).toString();
                map["duration"]    = query.value(5).toInt();
                map["trackNumber"] = query.value(6).toInt();
                list.append(map);
            }
        }
        closeConnection(db);
        QMetaObject::invokeMethod(this, [this, generation, list]() {
            if (generation == m_loadGeneration)
                emit tracksLoaded(list);
        });
    });
}

int MusicLibraryManager::scanProgress() const {
    return m_scanProgress;
}

void MusicLibraryManager::onScanProgress(int current, int total) {
    m_scanProgress = total > 0 ? current * 100 / total : 0;
    emit scanProgressChanged(m_scanProgress);
}

void MusicLibraryManager::onScanFinished(int trackCount, const QList<Artist> &artists) {
    m_trackCount = trackCount;
    m_artists    = artists;
    m_isScanning = false;
    emit scanningChanged(false);
    emit scanComplete(m_trackCount);
    emit libraryChanged();
}

QStringList MusicLibraryManager::getScanPaths() {
    QStringList paths;

    QString     musicPath = QStandardPaths::writableLocation(QStandardPaths::MusicLocation);
    QDir        musicDir(musicPath);

    if (!musicDir.exists()) {
        musicDir.mkpath(musicPath);
    }

    paths << musicPath;

    return paths;
}

void MusicLibraryManager::onDirectoryChanged(const QString &path) {
    qDebug() << "[MusicLibraryManager] Directory changed:" << path;
    m_scanTimer->start();
}

void MusicLibraryManager::initDatabase() {
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QString dbDir   = dataDir + "/marathon";
    QDir().mkpath(dbDir);
    m_dbPath = dbDir + "/musiclibrary.db";

    QSqlDatabase db = openConnection(m_dbPath, "musiclibrary-init-");
    {
        QSqlQuery query(db);
        if (!query.exec("CREATE TABLE IF NOT EXISTS tracks ("
                        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
                        "path TEXT NOT NULL UNIQUE, "
                        "title TEXT, "
                        "artist TEXT, "
                        "album TEXT, "
                        "duration INTEGER DEFAULT 0, "
                        "track_number INTEGER DEFAULT 0, "
                        "year TEXT)"))
            qWarning() << "[MusicLibraryManager] Failed to create table:"
                       << query.lastError().text();
    }
    closeConnection(db);
}
