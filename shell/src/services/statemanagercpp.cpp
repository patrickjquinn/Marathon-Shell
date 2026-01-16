#include "statemanagercpp.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

StateManagerCpp::StateManagerCpp(QObject *parent)
    : QObject(parent)
    , m_settings("MarathonOS", "Shell") {
    loadStateData();
    scheduleAutoSave();
}

void StateManagerCpp::registerApp(const QString &appId, bool isVisible) {
    if (appId.isEmpty())
        return;

    m_runningApps[appId] = mapForRunningApp(appId, isVisible);
}

void StateManagerCpp::unregisterApp(const QString &appId) {
    if (appId.isEmpty())
        return;

    m_runningApps.remove(appId);
}

void StateManagerCpp::updateAppVisibility(const QString &appId, bool isVisible) {
    if (!m_runningApps.contains(appId))
        return;

    m_runningApps[appId] = mapForRunningApp(appId, isVisible);
}

void StateManagerCpp::saveAppState(const QString &appId, const QString &state) {
    if (appId.isEmpty())
        return;

    m_appStates[appId] = mapForState(state);
}

void StateManagerCpp::saveAllStates() {
    const QStringList appIds     = m_runningApps.keys();
    const QJsonArray  appIdArray = QJsonArray::fromStringList(appIds);

    QJsonObject       statesObject;
    for (auto it = m_appStates.constBegin(); it != m_appStates.constEnd(); ++it) {
        if (it.value().canConvert<QVariantMap>())
            statesObject.insert(it.key(), QJsonObject::fromVariantMap(it.value().toMap()));
    }

    m_settings.setValue(
        "AppState/runningAppIds",
        QString::fromUtf8(QJsonDocument(appIdArray).toJson(QJsonDocument::Compact)));
    m_settings.setValue(
        "AppState/appStateData",
        QString::fromUtf8(QJsonDocument(statesObject).toJson(QJsonDocument::Compact)));
    m_settings.sync();
}

QStringList StateManagerCpp::restoreStates() {
    const QString raw = m_settings.value("AppState/runningAppIds").toString();
    if (raw.isEmpty())
        return {};

    const QJsonDocument doc = QJsonDocument::fromJson(raw.toUtf8());
    if (!doc.isArray())
        return {};

    QStringList      appIds;
    const QJsonArray arr = doc.array();
    appIds.reserve(arr.size());
    for (const QJsonValue &value : arr) {
        if (value.isString())
            appIds.append(value.toString());
    }
    return appIds;
}

QVariantMap StateManagerCpp::getAppState(const QString &appId) const {
    return m_appStates.value(appId).toMap();
}

void StateManagerCpp::clearAppState(const QString &appId) {
    m_appStates.remove(appId);
}

void StateManagerCpp::clearAllStates() {
    m_runningApps.clear();
    m_appStates.clear();
    m_settings.setValue("AppState/runningAppIds", "");
    m_settings.setValue("AppState/appStateData", "");
    m_settings.sync();
}

void StateManagerCpp::loadStateData() {
    const QString rawStates = m_settings.value("AppState/appStateData").toString();
    if (rawStates.isEmpty())
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(rawStates.toUtf8());
    if (!doc.isObject())
        return;

    const QJsonObject obj = doc.object();
    for (auto it = obj.constBegin(); it != obj.constEnd(); ++it)
        m_appStates.insert(it.key(), it.value().toObject().toVariantMap());
}

void StateManagerCpp::scheduleAutoSave() {
    m_autoSaveTimer.setInterval(5000);
    m_autoSaveTimer.setSingleShot(false);
    connect(&m_autoSaveTimer, &QTimer::timeout, this, &StateManagerCpp::saveAllStates);
    m_autoSaveTimer.start();
}

QVariantMap StateManagerCpp::mapForRunningApp(const QString &appId, bool isVisible) const {
    QVariantMap map;
    map["appId"]     = appId;
    map["isVisible"] = isVisible;
    map["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    return map;
}

QVariantMap StateManagerCpp::mapForState(const QString &state) const {
    QVariantMap map;
    map["state"]     = state;
    map["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    return map;
}
