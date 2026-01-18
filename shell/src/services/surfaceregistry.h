#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <qqml.h>

class SurfaceRegistry : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit SurfaceRegistry(QObject *parent = nullptr);

    Q_INVOKABLE void     registerSurface(int surfaceId, QObject *item);
    Q_INVOKABLE void     unregisterSurface(int surfaceId);
    Q_INVOKABLE QObject *getSurfaceItem(int surfaceId) const;

  private:
    void                          logMessage(const QString &message) const;

    QHash<int, QPointer<QObject>> m_surfaceMap;
};
