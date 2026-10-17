#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QStringList>

class MarathonAppRegistry : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

  public:
    enum AppType : quint8 {
        System,
        Marathon,
        Native
    };
    Q_ENUM(AppType)

    enum AppRoles : quint16 {
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
        DefaultForRole,
        BackgroundCapabilitiesRole,
        RequiresQtModulesRole
    };

    struct AppInfo {
        QString     id;
        QString     name;
        QString     icon;
        AppType     type = Marathon;
        QString     absolutePath;
        QString     entryPoint;
        QString     version;
        // Protected: a system app holding its permissions without asking.
        bool        isProtected = false;
        // Installed by the OS, or signed with a system key.
        bool isSystem = false;
        // The installed manifest's, for a system app; what the user approved
        // at install, for any other.
        QStringList permissions;
        QStringList searchKeywords;
        QString     deepLinksJson;
        QStringList categories;
        QStringList handlesUriSchemes;
        QStringList defaultFor;
        QStringList backgroundCapabilities;
        QStringList requiresQtModules;
        QString     toolkit = QStringLiteral("keel");

        AppInfo() = default;
        AppInfo(const QString &id, const QString &name, const QString &icon, AppType type,
                const QString &absolutePath, const QString &entryPoint, const QString &version,
                bool isProtected, const QStringList &permissions)
            : id(id)
            , name(name)
            , icon(icon)
            , type(type)
            , absolutePath(absolutePath)
            , entryPoint(entryPoint)
            , version(version)
            , isProtected(isProtected)
            , permissions(permissions) {}
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
    Q_INVOKABLE QStringList getBackgroundCapabilities(const QString &appId) const;

    void                    registerAppInfo(const AppInfo &info);
    // Invalidates the app's AppInfo pointer.
    void                    unregisterApp(const QString &appId);
    AppInfo                *getAppInfo(const QString &appId);

  signals:
    void appRegistered(const QString &appId);
    void appUnregistered(const QString &appId);
    void countChanged();

  private:
    QVector<AppInfo *>        m_apps;
    QHash<QString, AppInfo *> m_appIndex;
};
