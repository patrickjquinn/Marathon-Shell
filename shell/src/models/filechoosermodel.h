#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QStringList>
#include <QVariantList>
#include <qqml.h>

// The file chooser's list: a folder's entries, folders first, filtered by
// name globs or MIME types; or files whose names hold `search` under the
// folder; or the recent files.
class FileChooserModel : public QAbstractListModel {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString folder READ folder WRITE setFolder NOTIFY folderChanged)
    Q_PROPERTY(QStringList nameFilters READ nameFilters WRITE setNameFilters NOTIFY filtersChanged)
    Q_PROPERTY(QStringList mimeFilters READ mimeFilters WRITE setMimeFilters NOTIFY filtersChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY filtersChanged)
    Q_PROPERTY(bool directoriesOnly READ directoriesOnly WRITE setDirectoriesOnly NOTIFY filtersChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    Q_PROPERTY(bool recent READ recent WRITE setRecent NOTIFY recentChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)

  public:
    enum Role : quint16 { NameRole = Qt::UserRole + 1, PathRole, IsDirRole, SizeRole, ModifiedRole, IsImageRole };

    static constexpr int kMaxSearchResults = 500;
    static constexpr int kMaxRecent        = 100;

    explicit FileChooserModel(QObject *parent = nullptr);

    int                    rowCount(const QModelIndex &parent = {}) const override;
    QVariant               data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString     folder() const { return m_folder; }
    void        setFolder(const QString &folder);
    QStringList nameFilters() const { return m_nameFilters; }
    void        setNameFilters(const QStringList &globs);
    QStringList mimeFilters() const { return m_mimeFilters; }
    void        setMimeFilters(const QStringList &mimes);
    bool        showHidden() const { return m_showHidden; }
    void        setShowHidden(bool show);
    bool        directoriesOnly() const { return m_directoriesOnly; }
    void        setDirectoriesOnly(bool only);
    QString     search() const { return m_search; }
    void        setSearch(const QString &search);
    bool        recent() const { return m_recent; }
    void        setRecent(bool recent);
    int         count() const { return int(m_entries.size()); }

    // Home and the media folders: [{name, path}]
    Q_INVOKABLE static QVariantList places();
    Q_INVOKABLE static bool         exists(const QString &path);
    Q_INVOKABLE static QString      join(const QString &folder, const QString &name);

  signals:
    void folderChanged();
    void filtersChanged();
    void searchChanged();
    void recentChanged();
    void countChanged();

  private:
    struct Entry {
        QString   name;
        QString   path;
        bool      isDir = false;
        qint64    size  = 0;
        QDateTime modified;
        bool      isImage = false;
    };

    void reload();
    bool accepts(const QString &path, bool isDir) const;
    void addRecent(QList<Entry> &entries) const;

    QString      m_folder;
    QStringList  m_nameFilters;
    QStringList  m_mimeFilters;
    bool         m_showHidden      = false;
    bool         m_directoriesOnly = false;
    QString      m_search;
    bool         m_recent = false;
    QList<Entry> m_entries;
};
