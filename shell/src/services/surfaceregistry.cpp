#include "surfaceregistry.h"

#include <QDebug>
#include <QtGlobal>

SurfaceRegistry::SurfaceRegistry(QObject *parent)
    : QObject(parent) {}

void SurfaceRegistry::registerSurface(int surfaceId, QObject *item) {
    if (surfaceId == -1 || !item) {
        return;
    }
    m_surfaceMap.insert(surfaceId, item);
    logMessage(QString("Registered surface: %1").arg(surfaceId));
}

void SurfaceRegistry::unregisterSurface(int surfaceId) {
    if (m_surfaceMap.remove(surfaceId) > 0) {
        logMessage(QString("Unregistered surface: %1").arg(surfaceId));
    }
}

QObject *SurfaceRegistry::getSurfaceItem(int surfaceId) const {
    const auto it = m_surfaceMap.constFind(surfaceId);
    if (it == m_surfaceMap.constEnd()) {
        return nullptr;
    }
    return it.value();
}

void SurfaceRegistry::logMessage(const QString &message) const {
    const QByteArray debugEnv = qgetenv("MARATHON_DEBUG").trimmed();
    if (!(debugEnv == "1" || debugEnv == "true")) {
        return;
    }
    qDebug().noquote() << "[INFO]" << "SurfaceRegistry:" << message;
}
