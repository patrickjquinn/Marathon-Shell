#include "appmodel.h"
#include "marathonappregistry.h"
#include <QDebug>

AppModel::AppModel(QObject* parent)
    : QAbstractListModel(parent)
{
    initializeMarathonApps();
}

AppModel::~AppModel()
{
    qDeleteAll(m_apps);
}

int AppModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid())
        return 0;
    return m_apps.count();
}

QVariant AppModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() >= m_apps.count())
        return QVariant();

    App* app = m_apps.at(index.row());

    switch (role) {
    case IdRole:
        return app->id();
    case NameRole:
        return app->name();
    case IconRole:
        return app->icon();
    case TypeRole:
        return app->type();
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[NameRole] = "name";
    roles[IconRole] = "icon";
    roles[TypeRole] = "type";
    return roles;
}

App* AppModel::getApp(const QString& appId)
{
    return m_appIndex.value(appId, nullptr);
}

App* AppModel::getAppAtIndex(int index)
{
    if (index < 0 || index >= m_apps.count())
        return nullptr;
    return m_apps.at(index);
}

void AppModel::addApp(const QString& id, const QString& name, const QString& icon, const QString& type)
{
    // Check if app already exists
    if (m_appIndex.contains(id)) {
        qDebug() << "[AppModel] App already exists:" << id;
        return;
    }

    beginInsertRows(QModelIndex(), m_apps.count(), m_apps.count());
    App* app = new App(id, name, icon, type, this);
    m_apps.append(app);
    m_appIndex[id] = app;
    endInsertRows();

    emit countChanged();
    qDebug() << "[AppModel] Added app:" << name << "(" << type << ")";
}

void AppModel::removeApp(const QString& appId)
{
    App* app = m_appIndex.value(appId, nullptr);
    if (!app) {
        qDebug() << "[AppModel] App not found:" << appId;
        return;
    }

    int index = m_apps.indexOf(app);
    if (index >= 0) {
        beginRemoveRows(QModelIndex(), index, index);
        m_apps.remove(index);
        m_appIndex.remove(appId);
        endRemoveRows();

        emit countChanged();
        delete app;
        qDebug() << "[AppModel] Removed app:" << appId;
    }
}

void AppModel::clear()
{
    beginResetModel();
    qDeleteAll(m_apps);
    m_apps.clear();
    m_appIndex.clear();
    endResetModel();

    emit countChanged();
    qDebug() << "[AppModel] Cleared all apps";
}

QString AppModel::getAppName(const QString& appId)
{
    App* app = getApp(appId);
    return app ? app->name() : appId;
}

QString AppModel::getAppIcon(const QString& appId)
{
    App* app = getApp(appId);
    return app ? app->icon() : QString();
}

bool AppModel::isNativeApp(const QString& appId)
{
    App* app = getApp(appId);
    return app ? (app->type() == "native") : false;
}

void AppModel::initializeMarathonApps()
{
    // Initialize with built-in Marathon apps (placeholders)
    // These will be replaced by dynamically loaded apps from the registry
    addApp("phone", "Phone", "qrc:/images/phone.svg", "marathon");
    addApp("messages", "Messages", "qrc:/images/messages.svg", "marathon");
    addApp("browser", "Browser", "qrc:/images/browser.svg", "marathon");
    addApp("camera", "Camera", "qrc:/images/camera.svg", "marathon");
    addApp("gallery", "Gallery", "qrc:/images/gallery.svg", "marathon");
    addApp("music", "Music", "qrc:/images/music.svg", "marathon");
    addApp("calendar", "Calendar", "qrc:/images/calendar.svg", "marathon");
    addApp("clock", "Clock", "qrc:/images/clock.svg", "marathon");
    addApp("maps", "Maps", "qrc:/images/maps.svg", "marathon");
    addApp("notes", "Notes", "qrc:/images/notes.svg", "marathon");

    qDebug() << "[AppModel] Initialized with" << m_apps.count() << "Marathon apps";
}

void AppModel::loadFromRegistry(QObject* registryObj)
{
    MarathonAppRegistry* registry = qobject_cast<MarathonAppRegistry*>(registryObj);
    if (!registry) {
        qWarning() << "[AppModel] Invalid registry object";
        return;
    }
    
    qDebug() << "[AppModel] Loading apps from registry...";
    
    QStringList appIds = registry->getAllAppIds();
    for (const QString& appId : appIds) {
        QVariantMap appInfo = registry->getApp(appId);
        
        QString id = appInfo.value("id").toString();
        QString name = appInfo.value("name").toString();
        QString icon = appInfo.value("icon").toString();
        int typeInt = appInfo.value("type").toInt();
        
        // Convert type enum to string
        QString type = "marathon";
        if (typeInt == MarathonAppRegistry::Native) {
            type = "native";
        } else if (typeInt == MarathonAppRegistry::System) {
            type = "marathon";
        }
        
        // Convert relative icon path to absolute if needed
        QString absolutePath = appInfo.value("absolutePath").toString();
        if (!icon.isEmpty() && !icon.startsWith("qrc:") && !icon.startsWith("file://")) {
            if (!icon.startsWith("/")) {
                icon = absolutePath + "/" + icon;
            }
            // Add file:// prefix for filesystem paths
            icon = "file://" + icon;
        }
        
        // Add or update app
        if (m_appIndex.contains(id)) {
            qDebug() << "[AppModel] Updating app from registry:" << id;
            // For now, just log. In future, we could update the existing app
        } else {
            addApp(id, name, icon, type);
            qDebug() << "[AppModel] Added app from registry:" << id;
        }
    }
    
    qDebug() << "[AppModel] Loaded" << appIds.count() << "apps from registry";
}

