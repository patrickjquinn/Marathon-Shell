#pragma once

class QQmlEngine;
class QJSEngine;

#include <QHash>
#include <QObject>
#include <QPointer>
#include <qqml.h>

class SurfaceRegistry : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static SurfaceRegistry *create(QQmlEngine *, QJSEngine *);

  public:
    explicit SurfaceRegistry(QObject *parent = nullptr);

    Q_INVOKABLE void     registerSurface(int surfaceId, QObject *item);
    Q_INVOKABLE void     unregisterSurface(int surfaceId);
    Q_INVOKABLE QObject *getSurfaceItem(int surfaceId) const;

  signals:
    void surfaceRegistered(int surfaceId);
    void surfaceUnregistered(int surfaceId);

  private:
    void                          logMessage(const QString &message) const;

    QHash<int, QPointer<QObject>> m_surfaceMap;
};
