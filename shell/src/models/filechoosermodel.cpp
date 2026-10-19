#include "filechoosermodel.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <QXmlStreamReader>

#include <algorithm>

namespace {
    constexpr int kRecentDays   = 30;
    constexpr int kVisitedLimit = 20000;

    QMimeType mimeOf(const QString &path) {
        static const QMimeDatabase db;
        return db.mimeTypeForFile(path, QMimeDatabase::MatchExtension);
    }
} // namespace

FileChooserModel::FileChooserModel(QObject *parent)
    : QAbstractListModel(parent) {}

int FileChooserModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : int(m_entries.size());
}

QVariant FileChooserModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case NameRole: return entry.name;
    case PathRole: return entry.path;
    case IsDirRole: return entry.isDir;
    case SizeRole: return entry.size;
    case ModifiedRole: return entry.modified;
    case IsImageRole: return entry.isImage;
    case UrlRole: return QUrl::fromLocalFile(entry.path);
    default: return {};
    }
}

QHash<int, QByteArray> FileChooserModel::roleNames() const {
    return {{NameRole, "name"},   {PathRole, "path"},         {IsDirRole, "isDir"},
            {SizeRole, "size"},   {ModifiedRole, "modified"}, {IsImageRole, "isImage"},
            {UrlRole, "url"}};
}

void FileChooserModel::setFolder(const QString &folder) {
    if (folder == m_folder)
        return;
    m_folder = folder;
    emit folderChanged();
    reload();
}

void FileChooserModel::setNameFilters(const QStringList &globs) {
    if (globs == m_nameFilters)
        return;
    m_nameFilters = globs;
    emit filtersChanged();
    reload();
}

void FileChooserModel::setMimeFilters(const QStringList &mimes) {
    if (mimes == m_mimeFilters)
        return;
    m_mimeFilters = mimes;
    emit filtersChanged();
    reload();
}

void FileChooserModel::setShowHidden(bool show) {
    if (show == m_showHidden)
        return;
    m_showHidden = show;
    emit filtersChanged();
    reload();
}

void FileChooserModel::setDirectoriesOnly(bool only) {
    if (only == m_directoriesOnly)
        return;
    m_directoriesOnly = only;
    emit filtersChanged();
    reload();
}

void FileChooserModel::setSearch(const QString &search) {
    if (search == m_search)
        return;
    m_search = search;
    emit searchChanged();
    reload();
}

void FileChooserModel::setRecent(bool recent) {
    if (recent == m_recent)
        return;
    m_recent = recent;
    emit recentChanged();
    reload();
}

QVariantList FileChooserModel::places() {
    QVariantList out{QVariantMap{{QStringLiteral("name"), tr("Home")},
                                 {QStringLiteral("path"), QDir::homePath()}}};
    const QList<QPair<QStandardPaths::StandardLocation, QString>> media{
        {QStandardPaths::DocumentsLocation, tr("Documents")},
        {QStandardPaths::DownloadLocation, tr("Downloads")},
        {QStandardPaths::PicturesLocation, tr("Pictures")},
        {QStandardPaths::MusicLocation, tr("Music")},
        {QStandardPaths::MoviesLocation, tr("Videos")}};
    for (const auto &[location, name] : media) {
        const QString path = QStandardPaths::writableLocation(location);
        if (!path.isEmpty() && path != QDir::homePath() && QFileInfo(path).isDir())
            out << QVariantMap{{QStringLiteral("name"), name}, {QStringLiteral("path"), path}};
    }
    const QString dcim = QDir::homePath() + QStringLiteral("/DCIM");
    if (QFileInfo(dcim).isDir())
        out << QVariantMap{{QStringLiteral("name"), tr("Camera")}, {QStringLiteral("path"), dcim}};
    return out;
}

bool FileChooserModel::exists(const QString &path) {
    return QFileInfo::exists(path);
}

QString FileChooserModel::join(const QString &folder, const QString &name) {
    return QDir(folder).filePath(name);
}

bool FileChooserModel::accepts(const QString &path, bool isDir) const {
    if (isDir)
        return true;
    if (m_directoriesOnly)
        return false;
    if (m_nameFilters.isEmpty() && m_mimeFilters.isEmpty())
        return true;
    const QString name = QFileInfo(path).fileName();
    for (const QString &glob : m_nameFilters) {
        if (QRegularExpression(QRegularExpression::wildcardToRegularExpression(glob),
                               QRegularExpression::CaseInsensitiveOption)
                .match(name)
                .hasMatch())
            return true;
    }
    if (m_mimeFilters.isEmpty())
        return false;
    const QMimeType type = mimeOf(path);
    return std::any_of(m_mimeFilters.cbegin(), m_mimeFilters.cend(), [&type](const QString &mime) {
        if (mime.endsWith(QLatin1String("/*")))
            return type.name().startsWith(mime.chopped(1));
        return type.inherits(mime);
    });
}

void FileChooserModel::addRecent(QList<Entry> &entries) const {
    const QDateTime since = QDateTime::currentDateTime().addDays(-kRecentDays);
    QSet<QString>   seen;
    const auto      add = [&](const QFileInfo &info) {
        if (!info.isFile() || info.isHidden() || info.lastModified() < since ||
            seen.contains(info.absoluteFilePath()) || !accepts(info.absoluteFilePath(), false))
            return;
        seen.insert(info.absoluteFilePath());
        entries << Entry{info.fileName(), info.absoluteFilePath(), false, info.size(),
                         info.lastModified(), mimeOf(info.absoluteFilePath()).name().startsWith(QLatin1String("image/"))};
    };

    QFile xbel(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) +
               QStringLiteral("/recently-used.xbel"));
    if (xbel.open(QIODevice::ReadOnly)) {
        QXmlStreamReader xml(&xbel);
        while (!xml.atEnd() && !xml.hasError()) {
            xml.readNext();
            if (xml.isStartElement() && xml.name() == QLatin1String("bookmark")) {
                const QUrl url(xml.attributes().value(QLatin1String("href")).toString());
                if (url.isLocalFile())
                    add(QFileInfo(url.toLocalFile()));
            }
        }
    }

    int visited = 0;
    const QVariantList folders = places();
    for (const QVariant &place : folders) {
        const QString path = place.toMap().value(QStringLiteral("path")).toString();
        if (path == QDir::homePath())
            continue;
        QDirIterator it(path, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext() && ++visited < kVisitedLimit)
            add(it.nextFileInfo());
    }
    std::sort(entries.begin(), entries.end(),
              [](const Entry &a, const Entry &b) { return a.modified > b.modified; });
    if (entries.size() > kMaxRecent)
        entries.resize(kMaxRecent);
}

void FileChooserModel::reload() {
    QList<Entry> entries;
    if (m_recent) {
        addRecent(entries);
    } else if (!m_search.isEmpty() && !m_folder.isEmpty()) {
        QDirIterator it(m_folder, QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot,
                        QDirIterator::Subdirectories);
        int visited = 0;
        while (it.hasNext() && ++visited < kVisitedLimit && entries.size() < kMaxSearchResults) {
            const QFileInfo info = it.nextFileInfo();
            if ((!m_showHidden && info.isHidden()) || !info.fileName().contains(m_search, Qt::CaseInsensitive) ||
                info.isDir() || !accepts(info.absoluteFilePath(), false))
                continue;
            entries << Entry{info.fileName(), info.absoluteFilePath(), false, info.size(), info.lastModified(),
                             mimeOf(info.absoluteFilePath()).name().startsWith(QLatin1String("image/"))};
        }
    } else if (!m_folder.isEmpty()) {
        QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
        if (m_showHidden)
            filters |= QDir::Hidden;
        const QFileInfoList infos =
            QDir(m_folder).entryInfoList(filters, QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
        for (const QFileInfo &info : infos) {
            if (!accepts(info.absoluteFilePath(), info.isDir()))
                continue;
            entries << Entry{info.fileName(), info.absoluteFilePath(), info.isDir(), info.size(),
                             info.lastModified(),
                             !info.isDir() && mimeOf(info.absoluteFilePath()).name().startsWith(QLatin1String("image/"))};
        }
    }
    const bool countChanges = entries.size() != m_entries.size();
    beginResetModel();
    m_entries = entries;
    endResetModel();
    if (countChanges)
        emit countChanged();
}
