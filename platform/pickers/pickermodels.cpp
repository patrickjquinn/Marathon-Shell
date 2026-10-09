// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "pickermodels.h"

#include "filesource.h"
#include "trackersource.h"

#include <QDir>
#include <QCoreApplication>
#include <QFileInfo>
#include <QLoggingCategory>
#include <QMimeDatabase>
#include <QPointer>

Q_LOGGING_CATEGORY(lcKeelPickers, "keel.pickers")

using keel::pickers::Category;
using keel::pickers::ContentItem;

// ---------------------------------------------------------------------------
// KeelPickerListModel
// ---------------------------------------------------------------------------

int KeelPickerListModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : static_cast<int>(m_items.size());
}

QVariant KeelPickerListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const ContentItem &item = m_items.at(index.row());
    switch (role) {
    case FileNameRole:
        return item.fileName;
    case FilePathRole:
        return item.filePath;
    case UrlRole:
        return item.url();
    case TitleRole:
    case Qt::DisplayRole:
        return item.title;
    case MimeTypeRole:
        return item.mimeType;
    case FileSizeRole:
        return item.fileSize;
    case LastModifiedRole:
        return item.lastModified;
    case IsDirRole:
        return item.isDir;
    case SelectedRole:
        return item.selected;
    case ContentTypeRole:
        return keel::pickers::categoryName(item.category);
    default:
        return {};
    }
}

QHash<int, QByteArray> KeelPickerListModel::roleNames() const
{
    return {
        { FileNameRole, "fileName" },       { FilePathRole, "filePath" }, { UrlRole, "url" },
        { TitleRole, "title" },             { MimeTypeRole, "mimeType" }, { FileSizeRole, "fileSize" },
        { LastModifiedRole, "lastModified" }, { IsDirRole, "isDir" },     { SelectedRole, "selected" },
        { ContentTypeRole, "contentType" },
    };
}

int KeelPickerListModel::selectedCount() const
{
    return static_cast<int>(std::count_if(m_items.cbegin(), m_items.cend(), [](const ContentItem &i) { return i.selected; }));
}

QVariantMap KeelPickerListModel::get(int row) const
{
    if (row < 0 || row >= m_items.size())
        return {};
    return m_items.at(row).toMap();
}

void KeelPickerListModel::setSelected(int row, bool selected)
{
    if (row < 0 || row >= m_items.size() || m_items.at(row).selected == selected)
        return;
    m_items[row].selected = selected;
    const QModelIndex i = index(row);
    emit dataChanged(i, i, { SelectedRole });
    emit selectedCountChanged();
}

void KeelPickerListModel::toggleSelected(int row)
{
    if (row >= 0 && row < m_items.size())
        setSelected(row, !m_items.at(row).selected);
}

void KeelPickerListModel::clearSelection()
{
    for (int row = 0; row < m_items.size(); ++row)
        setSelected(row, false);
}

QVariantList KeelPickerListModel::selectedItems() const
{
    QVariantList out;
    for (const ContentItem &item : m_items) {
        if (item.selected)
            out.append(item.toMap());
    }
    return out;
}

void KeelPickerListModel::resetItems(QList<ContentItem> items)
{
    const int oldCount = count();
    const int oldSelected = selectedCount();
    beginResetModel();
    m_items = std::move(items);
    endResetModel();
    if (count() != oldCount)
        emit countChanged();
    if (selectedCount() != oldSelected)
        emit selectedCountChanged();
}

// ---------------------------------------------------------------------------
// KeelContentModel
// ---------------------------------------------------------------------------

namespace {

Category categoryOf(KeelContentModel::ContentType type)
{
    switch (type) {
    case KeelContentModel::DocumentContent:
        return Category::Document;
    case KeelContentModel::ImageContent:
        return Category::Image;
    case KeelContentModel::VideoContent:
        return Category::Video;
    case KeelContentModel::MusicContent:
        return Category::Music;
    case KeelContentModel::DownloadContent:
        return Category::Download;
    case KeelContentModel::FileContent:
        return Category::File;
    case KeelContentModel::AnyContent:
        break;
    }
    return Category::Any;
}

bool trackerAllowed()
{
    return qEnvironmentVariable("KEEL_PICKERS_TRACKER") != QLatin1String("0");
}

} // namespace

KeelContentModel::KeelContentModel(QObject *parent)
    : KeelPickerListModel(parent)
{
}

KeelContentModel::~KeelContentModel()
{
    if (m_cancel)
        m_cancel->store(true);
    // A scan stops at its next entry; a Tracker query within its timeout.
    if (m_worker && !m_worker->wait(5000)) {
        // Still blocked in D-Bus: leave the thread object be (it is not
        // deleted while running).
        QThread *stuck = m_worker.release();
        Q_UNUSED(stuck)
    }
}

void KeelContentModel::setContentType(ContentType type)
{
    if (m_contentType == type)
        return;
    m_contentType = type;
    emit contentTypeChanged();
    if (m_complete)
        reload();
}

void KeelContentModel::setNameFilters(const QStringList &filters)
{
    if (m_nameFilters == filters)
        return;
    m_nameFilters = filters;
    emit nameFiltersChanged();
    if (m_complete)
        reload();
}

void KeelContentModel::setFilter(const QString &filter)
{
    if (m_filter == filter)
        return;
    m_filter = filter;
    emit filterChanged();
    applyFilter();
}

void KeelContentModel::componentComplete()
{
    m_complete = true;
    reload();
}

void KeelContentModel::stopWorker()
{
    if (m_cancel)
        m_cancel->store(true);
    if (m_worker) {
        // The worker only touches its own copies; let it finish on its own.
        QThread *t = m_worker.release();
        QObject::connect(t, &QThread::finished, t, &QObject::deleteLater);
        if (t->isFinished())
            t->deleteLater();
    }
}

void KeelContentModel::reload()
{
    stopWorker();
    const quint64 generation = ++m_generation;
    if (!m_loading) {
        m_loading = true;
        emit loadingChanged();
    }
    const Category category = categoryOf(m_contentType);
    const QStringList filters = m_nameFilters;
    auto cancel = std::make_shared<std::atomic_bool>(false);
    m_cancel = cancel;
    QPointer<KeelContentModel> self(this);
    m_worker.reset(QThread::create([self, generation, category, filters, cancel]() {
        QList<ContentItem> items;
        QString source;
        // Tracker indexes the four media categories; downloads, plain files
        // and name-filtered lists come from the filesystem.
        const bool tracker = trackerAllowed() && filters.isEmpty()
            && (category == Category::Image || category == Category::Video || category == Category::Music
                || category == Category::Document || category == Category::Any)
            && keel::pickers::TrackerSource::available();
        if (tracker) {
            QString error;
            const QList<Category> cats = category == Category::Any
                ? QList<Category> { Category::Document, Category::Image, Category::Video, Category::Music }
                : QList<Category> { category };
            bool ok = true;
            for (Category c : cats) {
                if (!keel::pickers::TrackerSource::fetch(c, kLimit, &items, &error)) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                const QString music = keel::pickers::FileSource::musicDir();
                items.erase(std::remove_if(items.begin(), items.end(),
                                           [&](const ContentItem &i) {
                                               return i.category == Category::Image && !music.isEmpty()
                                                   && i.filePath.startsWith(music + QLatin1Char('/'));
                                           }),
                            items.end());
                std::stable_sort(items.begin(), items.end(), [](const ContentItem &a, const ContentItem &b) {
                    return a.lastModified > b.lastModified;
                });
                source = QStringLiteral("tracker");
            } else {
                qCWarning(lcKeelPickers) << "Tracker query failed, scanning the filesystem:" << error;
                items.clear();
            }
        }
        if (source.isEmpty()) {
            items = keel::pickers::FileSource::scan(category, filters, kLimit, *cancel);
            source = QStringLiteral("filesystem");
        }
        if (cancel->load())
            return;
        // Back to the GUI thread (the application object lives there); the
        // QPointer is only read on that side.
        QMetaObject::invokeMethod(
            QCoreApplication::instance(),
            [self, generation, items, source]() {
                if (self)
                    self->finishLoad(generation, items, source);
            },
            Qt::QueuedConnection);
    }));
    m_worker->start();
}

void KeelContentModel::finishLoad(quint64 generation, const QList<ContentItem> &items, const QString &source)
{
    if (generation != m_generation)
        return;
    m_all = items;
    if (m_source != source) {
        m_source = source;
        emit sourceChanged();
    }
    applyFilter();
    if (m_loading) {
        m_loading = false;
        emit loadingChanged();
    }
}

void KeelContentModel::applyFilter()
{
    if (m_filter.isEmpty()) {
        resetItems(m_all);
        return;
    }
    QList<ContentItem> shown;
    for (const ContentItem &i : std::as_const(m_all)) {
        if (i.fileName.contains(m_filter, Qt::CaseInsensitive) || i.title.contains(m_filter, Qt::CaseInsensitive))
            shown.append(i);
    }
    resetItems(shown);
}

// ---------------------------------------------------------------------------
// KeelFolderModel
// ---------------------------------------------------------------------------

KeelFolderModel::KeelFolderModel(QObject *parent)
    : KeelPickerListModel(parent)
    , m_path(homePath())
{
    refresh();
}

QString KeelFolderModel::homePath()
{
    return QDir::homePath();
}

void KeelFolderModel::setPath(const QString &path)
{
    QString clean = path.isEmpty() ? homePath() : QDir::cleanPath(path);
    if (clean.startsWith(QLatin1String("file://")))
        clean = QUrl(clean).toLocalFile();
    if (m_path == clean)
        return;
    m_path = clean;
    emit pathChanged();
    refresh();
}

QString KeelFolderModel::parentPath() const
{
    if (m_path == QLatin1String("/"))
        return {};
    return QFileInfo(m_path).path();
}

bool KeelFolderModel::canGoUp() const
{
    if (m_path == QLatin1String("/"))
        return false;
    if (m_showSystemFiles)
        return true;
    const QString home = homePath();
    return m_path != home && m_path.startsWith(home + QLatin1Char('/'));
}

void KeelFolderModel::setShowSystemFiles(bool show)
{
    if (m_showSystemFiles == show)
        return;
    m_showSystemFiles = show;
    emit showSystemFilesChanged();
    emit pathChanged(); // canGoUp
    refresh();
}

void KeelFolderModel::setIncludeFiles(bool include)
{
    if (m_includeFiles == include)
        return;
    m_includeFiles = include;
    emit includeFilesChanged();
    refresh();
}

void KeelFolderModel::setNameFilters(const QStringList &filters)
{
    if (m_nameFilters == filters)
        return;
    m_nameFilters = filters;
    emit nameFiltersChanged();
    refresh();
}

void KeelFolderModel::refresh()
{
    QDir::Filters filters = QDir::Dirs | QDir::NoDotAndDotDot | QDir::Readable;
    if (m_includeFiles)
        filters |= QDir::Files;
    if (m_showSystemFiles)
        filters |= QDir::Hidden | QDir::System;
    const QFileInfoList entries
        = QDir(m_path).entryInfoList(filters, QDir::DirsFirst | QDir::Name | QDir::IgnoreCase);
    QMimeDatabase mimes;
    QList<ContentItem> items;
    items.reserve(entries.size());
    for (const QFileInfo &info : entries) {
        ContentItem item;
        item.isDir = info.isDir();
        if (!item.isDir && !keel::pickers::matchesNameFilters(info.fileName(), m_nameFilters))
            continue;
        item.fileName = info.fileName();
        item.filePath = info.filePath();
        item.title = info.fileName();
        item.mimeType = item.isDir ? QStringLiteral("inode/directory")
                                   : mimes.mimeTypeForFile(info, QMimeDatabase::MatchExtension).name();
        item.fileSize = item.isDir ? 0 : info.size();
        item.lastModified = info.lastModified();
        item.category = item.isDir ? Category::File : keel::pickers::categoryForMime(item.mimeType);
        items.append(item);
    }
    resetItems(items);
}
