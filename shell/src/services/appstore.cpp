#include "appstore.h"
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

QVariantMap AppStore::getApp(const QString &appId) const {
    if (!m_appRegistry) {
        return {};
    }
    return m_appRegistry->getApp(appId);
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

bool AppStore::isInternalApp(const QString &appId) const {
    const QVariantMap app = getApp(appId);
    if (app.isEmpty()) {
        return true;
    }
    return app.value("type").toInt() == static_cast<int>(MarathonAppRegistry::Marathon);
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
