#include "marathonappregistry.h"
#include <QDebug>

MarathonAppRegistry::MarathonAppRegistry(QObject *parent)
    : QAbstractListModel(parent) {
    qDebug() << "[MarathonAppRegistry] Initialized";
}

MarathonAppRegistry::~MarathonAppRegistry() {
    qDeleteAll(m_apps);
}

int MarathonAppRegistry::rowCount(const QModelIndex &parent) const {
    if (parent.isValid())
        return 0;
    return m_apps.count();
}

QVariant MarathonAppRegistry::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_apps.count())
        return QVariant();

    const AppInfo *app = m_apps.at(index.row());

    switch (role) {
        case IdRole: return app->id;
        case NameRole: return app->name;
        case IconRole: return app->icon;
        case TypeRole: return static_cast<int>(app->type);
        case PathRole: return app->absolutePath;
        case EntryPointRole: return app->entryPoint;
        case VersionRole: return app->version;
        case IsProtectedRole: return app->isProtected;
        case PermissionsRole: return app->permissions;
        case SearchKeywordsRole: return app->searchKeywords;
        case DeepLinksRole: return app->deepLinksJson;
        case CategoriesRole: return app->categories;
        case HandlesUriSchemesRole: return app->handlesUriSchemes;
        case DefaultForRole: return app->defaultFor;
        default: return QVariant();
    }
}

QHash<int, QByteArray> MarathonAppRegistry::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole]                = "id";
    roles[NameRole]              = "name";
    roles[IconRole]              = "icon";
    roles[TypeRole]              = "type";
    roles[PathRole]              = "absolutePath";
    roles[EntryPointRole]        = "entryPoint";
    roles[VersionRole]           = "version";
    roles[IsProtectedRole]       = "isProtected";
    roles[PermissionsRole]       = "permissions";
    roles[SearchKeywordsRole]    = "searchKeywords";
    roles[DeepLinksRole]         = "deepLinks";
    roles[CategoriesRole]        = "categories";
    roles[HandlesUriSchemesRole] = "handlesUriSchemes";
    roles[DefaultForRole]        = "defaultFor";
    return roles;
}

QVariantMap MarathonAppRegistry::getApp(const QString &appId) const {
    QVariantMap result;

    if (m_appIndex.contains(appId)) {
        const AppInfo *app          = m_appIndex.value(appId);
        result["id"]                = app->id;
        result["name"]              = app->name;
        result["icon"]              = app->icon;
        result["type"]              = static_cast<int>(app->type);
        result["absolutePath"]      = app->absolutePath;
        result["entryPoint"]        = app->entryPoint;
        result["version"]           = app->version;
        result["isProtected"]       = app->isProtected;
        result["permissions"]       = app->permissions;
        result["searchKeywords"]    = app->searchKeywords;
        result["deepLinks"]         = app->deepLinksJson;
        result["categories"]        = app->categories;
        result["handlesUriSchemes"] = app->handlesUriSchemes;
        result["defaultFor"]        = app->defaultFor;
    }

    return result;
}

void MarathonAppRegistry::registerApp(const QString &id, const QString &name, const QString &icon,
                                      int type, const QString &absolutePath,
                                      const QString &entryPoint, const QString &version,
                                      bool isProtected, const QStringList &permissions) {
    if (m_appIndex.contains(id)) {
        qWarning() << "[MarathonAppRegistry] App already registered:" << id;
        return;
    }

    AppInfo *info = new AppInfo{id,           name,       icon,    static_cast<AppType>(type),
                                absolutePath, entryPoint, version, isProtected,
                                permissions};

    registerAppInfo(*info);
}

void MarathonAppRegistry::registerAppInfo(const AppInfo &info) {
    if (m_appIndex.contains(info.id)) {
        qWarning() << "[MarathonAppRegistry] App already registered:" << info.id;
        return;
    }

    AppInfo *appInfo = new AppInfo(info);

    beginInsertRows(QModelIndex(), m_apps.size(), m_apps.size());
    m_apps.append(appInfo);
    m_appIndex.insert(info.id, appInfo);
    endInsertRows();

    emit appRegistered(info.id);
    emit countChanged();

    qDebug() << "[MarathonAppRegistry] Registered app:" << info.id << "| Name:" << info.name
             << "| Type:" << static_cast<int>(info.type) << "| Protected:" << info.isProtected;
}

bool MarathonAppRegistry::isProtected(const QString &appId) const {
    if (m_appIndex.contains(appId)) {
        return m_appIndex.value(appId)->isProtected;
    }
    return false;
}

bool MarathonAppRegistry::hasApp(const QString &appId) const {
    return m_appIndex.contains(appId);
}

QStringList MarathonAppRegistry::getAllAppIds() const {
    return m_appIndex.keys();
}

MarathonAppRegistry::AppInfo *MarathonAppRegistry::getAppInfo(const QString &appId) {
    return m_appIndex.value(appId, nullptr);
}
