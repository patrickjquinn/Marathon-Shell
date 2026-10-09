// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The list models behind Keel's Sailfish.Pickers pages. They are Keel's own
// types (not Sailfish API), registered in Sailfish.Pickers under Keel names
// for the module's QML.
//
// KeelContentModel  files of one category (documents, images, videos,
//                   music, downloads, any), newest first, from Tracker 3
//                   when the indexer is there, else from a scan of the
//                   user's directories (trackersource.h, filesource.h).
//                   Loads on a worker thread.
// KeelFolderModel   the entries of one directory (folders first), for the
//                   file and folder pickers.
// Both keep a per-row `selected` flag for the multi pickers.
#ifndef KEEL_PICKERS_PICKERMODELS_H
#define KEEL_PICKERS_PICKERMODELS_H

#include "contentitem.h"

#include <QAbstractListModel>
#include <QQmlParserStatus>
#include <QThread>
#include <QtQml/qqmlregistration.h>
#include <atomic>
#include <memory>

class KeelPickerListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY selectedCountChanged)
    QML_ANONYMOUS

public:
    enum Role {
        FileNameRole = Qt::UserRole + 1,
        FilePathRole,
        UrlRole,
        TitleRole,
        MimeTypeRole,
        FileSizeRole,
        LastModifiedRole,
        IsDirRole,
        SelectedRole,
        ContentTypeRole,
    };

    using QAbstractListModel::QAbstractListModel;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return static_cast<int>(m_items.size()); }
    int selectedCount() const;

    // The item's selectedContentProperties map (fileName, filePath, url,
    // title, mimeType, fileSize, lastModified, contentType).
    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE void setSelected(int row, bool selected);
    Q_INVOKABLE void toggleSelected(int row);
    Q_INVOKABLE void clearSelection();
    // Maps of the selected rows, in model order.
    Q_INVOKABLE QVariantList selectedItems() const;

signals:
    void countChanged();
    void selectedCountChanged();

protected:
    void resetItems(QList<keel::pickers::ContentItem> items);
    const QList<keel::pickers::ContentItem> &items() const { return m_items; }

private:
    QList<keel::pickers::ContentItem> m_items;
};

class KeelContentModel : public KeelPickerListModel, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(ContentType contentType READ contentType WRITE setContentType NOTIFY contentTypeChanged)
    Q_PROPERTY(QStringList nameFilters READ nameFilters WRITE setNameFilters NOTIFY nameFiltersChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(bool loading READ isLoading NOTIFY loadingChanged)
    Q_PROPERTY(QString source READ source NOTIFY sourceChanged)
    QML_ELEMENT

public:
    enum ContentType { AnyContent, DocumentContent, ImageContent, VideoContent, MusicContent,
                       DownloadContent, FileContent };
    Q_ENUM(ContentType)

    explicit KeelContentModel(QObject *parent = nullptr);
    ~KeelContentModel() override;

    ContentType contentType() const { return m_contentType; }
    void setContentType(ContentType type);
    QStringList nameFilters() const { return m_nameFilters; }
    void setNameFilters(const QStringList &filters);
    QString filter() const { return m_filter; }
    void setFilter(const QString &filter);
    bool isLoading() const { return m_loading; }
    // "tracker" or "filesystem": where the last load came from.
    QString source() const { return m_source; }

    Q_INVOKABLE void reload();

    void classBegin() override { }
    void componentComplete() override;

    static constexpr int kLimit = 5000;

signals:
    void contentTypeChanged();
    void nameFiltersChanged();
    void filterChanged();
    void loadingChanged();
    void sourceChanged();

private:
    void finishLoad(quint64 generation, const QList<keel::pickers::ContentItem> &items, const QString &source);
    void applyFilter();
    void stopWorker();

    ContentType m_contentType = AnyContent;
    QStringList m_nameFilters;
    QString m_filter;
    QString m_source;
    bool m_loading = false;
    bool m_complete = false;
    quint64 m_generation = 0;
    QList<keel::pickers::ContentItem> m_all;
    std::unique_ptr<QThread> m_worker;
    std::shared_ptr<std::atomic_bool> m_cancel;
};

class KeelFolderModel : public KeelPickerListModel
{
    Q_OBJECT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(QString parentPath READ parentPath NOTIFY pathChanged)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)
    Q_PROPERTY(bool canGoUp READ canGoUp NOTIFY pathChanged)
    Q_PROPERTY(bool showSystemFiles READ showSystemFiles WRITE setShowSystemFiles NOTIFY showSystemFilesChanged)
    Q_PROPERTY(bool includeFiles READ includeFiles WRITE setIncludeFiles NOTIFY includeFilesChanged)
    Q_PROPERTY(QStringList nameFilters READ nameFilters WRITE setNameFilters NOTIFY nameFiltersChanged)
    QML_ELEMENT

public:
    explicit KeelFolderModel(QObject *parent = nullptr);

    QString path() const { return m_path; }
    void setPath(const QString &path);
    QString parentPath() const;
    static QString homePath();
    // Above the home directory only with showSystemFiles (the
    // FolderPickerPage documentation: "whether the user can see root system
    // directory").
    bool canGoUp() const;
    bool showSystemFiles() const { return m_showSystemFiles; }
    void setShowSystemFiles(bool show);
    bool includeFiles() const { return m_includeFiles; }
    void setIncludeFiles(bool include);
    QStringList nameFilters() const { return m_nameFilters; }
    void setNameFilters(const QStringList &filters);

    Q_INVOKABLE void refresh();

signals:
    void pathChanged();
    void showSystemFilesChanged();
    void includeFilesChanged();
    void nameFiltersChanged();

private:
    QString m_path;
    bool m_showSystemFiles = false;
    bool m_includeFiles = true;
    QStringList m_nameFilters;
};

#endif // KEEL_PICKERS_PICKERMODELS_H
