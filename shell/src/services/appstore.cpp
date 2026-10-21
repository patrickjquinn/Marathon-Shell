#include "appstore.h"
#include "marathon-shell-native/src/apps.cxxqt.h"

AppStore::AppStore(Apps *apps, QObject *parent)
    : QObject(parent)
    , m_appModel(apps) {
    connect(apps, &Apps::registryChanged, this, &AppStore::refreshApps);
    // Names read through apps (the Hub's) look again as desktop apps load.
    connect(apps, &Apps::countChanged, this, &AppStore::appsChanged);
    refreshApps();
}

QVariantMap AppStore::getApp(const QString &appId) const {
    QVariantMap app = m_appModel ? m_appModel->getApp(appId) : QVariantMap();
    if (app.isEmpty() && m_appModel) {
        if (const QVariantMap a = m_appModel->findById(appId); !a.isEmpty())
            app = {{"id", a.value("id")}, {"name", a.value("name")}, {"icon", a.value("icon")}};
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

void AppStore::refreshApps() {
    if (!m_appModel)
        return;
    QVariantList      updated;
    const QStringList ids = m_appModel->getAllAppIds();
    for (const QString &id : ids)
        updated.append(m_appModel->getApp(id));
    m_apps = updated;
    emit appsChanged();
}
