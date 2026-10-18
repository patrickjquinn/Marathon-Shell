#include "appstore.h"
#include "appmodel.h"
#include "marathonappregistry.h"

AppStore::AppStore(MarathonAppRegistry *appRegistry, QObject *parent)
    : QObject(parent)
    , m_appRegistry(appRegistry) {
    if (m_appRegistry) {
        connect(m_appRegistry, &MarathonAppRegistry::appRegistered, this,
                [this]() { refreshApps(); });
        connect(m_appRegistry, &MarathonAppRegistry::appUnregistered, this,
                [this]() { refreshApps(); });
        connect(m_appRegistry, &MarathonAppRegistry::countChanged, this,
                [this]() { refreshApps(); });
    }
    refreshApps();
}

void AppStore::setAppModel(AppModel *apps) {
    m_appModel = apps;
    // Names read through apps (the Hub's) look again as desktop apps load.
    connect(apps, &AppModel::countChanged, this, &AppStore::appsChanged);
}

QVariantMap AppStore::getApp(const QString &appId) const {
    QVariantMap app = m_appRegistry ? m_appRegistry->getApp(appId) : QVariantMap();
    if (app.isEmpty() && m_appModel) {
        if (const App *a = m_appModel->getApp(appId))
            app = {{"id", a->id()}, {"name", a->name()}, {"icon", a->icon()}};
    }
    return app;
}

QString AppStore::getAppName(const QString &appId) const {
    const QVariantMap app  = getApp(appId);
    const QString     name = app.value("name").toString();
    return name.isEmpty() ? appId : name;
}

QString AppStore::getAppIcon(const QString &appId) const {
    const QVariantMap app = getApp(appId);
    return app.value("icon").toString();
}

bool AppStore::isNativeApp(const QString &appId) const {
    const QVariantMap app = getApp(appId);
    return app.value("type").toInt() == static_cast<int>(MarathonAppRegistry::Native);
}

void AppStore::refreshApps() {
    if (!m_appRegistry) {
        return;
    }
    QVariantList      updated;
    const QStringList ids = m_appRegistry->getAllAppIds();
    for (const QString &id : ids) {
        updated.append(m_appRegistry->getApp(id));
    }
    m_apps = updated;
    emit appsChanged();
}
