#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QStringList>

class MarathonAppRegistry : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

  public:
    enum AppType {
        System,
        Marathon,
        Native
    };
    Q_ENUM(AppType)

    enum AppRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        IconRole,
        TypeRole,
        PathRole,
        EntryPointRole,
        VersionRole,
        IsProtectedRole,
        PermissionsRole,
        SearchKeywordsRole,
        DeepLinksRole,
        CategoriesRole,
        HandlesUriSchemesRole,
        DefaultForRole
    };

    struct AppInfo {
        QString     id;
        QString     name;
        QString     icon;
        AppType     type;
        QString     absolutePath;
        QString     entryPoint;
        QString     version;
        bool        isProtected;
        QStringList permissions;
        QStringList searchKeywords;
        QString     deepLinksJson; // JSON string for QML parsing
        QStringList categories;
        QStringList handlesUriSchemes;
        QStringList defaultFor;
    };

    explicit MarathonAppRegistry(QObject *parent = nullptr);
    ~MarathonAppRegistry() override;

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int                    count() const {
        return m_apps.count();
    }

    Q_INVOKABLE QVariantMap getApp(const QString &appId) const;
    Q_INVOKABLE void        registerApp(const QString &id, const QString &name, const QString &icon,
                                        int type, const QString &absolutePath, const QString &entryPoint,
                                        const QString &version, bool isProtected,
                                        const QStringList &permissions);
    Q_INVOKABLE bool        isProtected(const QString &appId) const;
    Q_INVOKABLE bool        hasApp(const QString &appId) const;
    Q_INVOKABLE QStringList getAllAppIds() const;

    void                    registerAppInfo(const AppInfo &info);
    AppInfo                *getAppInfo(const QString &appId);

  signals:
    void appRegistered(const QString &appId);
    void appUnregistered(const QString &appId);
    void countChanged();

  private:
    QVector<AppInfo *>        m_apps;
    QHash<QString, AppInfo *> m_appIndex;
};
