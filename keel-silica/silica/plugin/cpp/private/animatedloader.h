// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// AnimatedLoader (Sailfish.Silica.private): a loader that keeps the item it
// replaces alive while the QML around it animates the change. API inferred
// from Silica's BSD QML (PageStack.qml, TabView.qml, ApplicationWindow.qml):
// `source` (a URL, a Component, or undefined), load(source, cacheKey,
// properties), `item`, `replacedItem`, `status` (Null, Ready, Loading,
// Error), `errorString`, `asynchronous`, `animating`, and the signals
// aboutToComplete(), initializeItem(item), animate(), completeAnimation(),
// error(errorString).
//
// Clean-room behaviour:
//  - aboutToComplete() is emitted while the loader completes, before it
//    loads `source` (when that is still unset, its handler may call load());
//  - load() creates the object (in the loader's context for a URL, in the
//    component's own for a Component) with `properties` as initial
//    properties, parented to the loader; asynchronously when `asynchronous`.
//    The component of a URL is made once per engine and kept (a page pushed
//    again does not go through the type loader again);
//  - a new item is announced with initializeItem(item), then becomes `item`
//    while the previous one becomes `replacedItem`, and animate() is
//    emitted; when `animating` is false (then, or later) the replaced item
//    is destroyed;
//  - a load that starts while an animation runs first emits
//    completeAnimation().
#ifndef KEEL_ANIMATEDLOADER_H
#define KEEL_ANIMATEDLOADER_H

#include <QPointer>
#include <QQmlComponent>
#include <QQmlIncubator>
#include <QQuickItem>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class KeelAnimatedLoader;

class KeelLoaderIncubator : public QQmlIncubator
{
public:
    KeelLoaderIncubator(KeelAnimatedLoader *loader, IncubationMode mode)
        : QQmlIncubator(mode)
        , m_loader(loader)
    {
    }

protected:
    void setInitialState(QObject *object) override;
    void statusChanged(Status status) override;

private:
    KeelAnimatedLoader *m_loader;
};

class KeelAnimatedLoader : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(AnimatedLoader)
    Q_PROPERTY(QVariant source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QQuickItem *item READ item NOTIFY itemChanged)
    Q_PROPERTY(QQuickItem *replacedItem READ replacedItem NOTIFY replacedItemChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY statusChanged)
    Q_PROPERTY(bool asynchronous READ asynchronous WRITE setAsynchronous NOTIFY asynchronousChanged)
    Q_PROPERTY(bool animating READ animating WRITE setAnimating NOTIFY animatingChanged)

public:
    enum Status { Null, Ready, Loading, Error };
    Q_ENUM(Status)

    explicit KeelAnimatedLoader(QQuickItem *parent = nullptr);
    ~KeelAnimatedLoader() override;

    QVariant source() const { return m_source; }
    void setSource(const QVariant &source);
    QQuickItem *item() const { return m_item; }
    QQuickItem *replacedItem() const { return m_replaced; }
    Status status() const { return m_status; }
    QString errorString() const { return m_errorString; }
    bool asynchronous() const { return m_asynchronous; }
    void setAsynchronous(bool a);
    bool animating() const { return m_animating; }
    void setAnimating(bool a);

    Q_INVOKABLE void load(const QVariant &source, const QVariant &cacheKey = QVariant(),
                          const QVariantMap &properties = QVariantMap());

signals:
    void sourceChanged();
    void itemChanged();
    void replacedItemChanged();
    void statusChanged();
    void asynchronousChanged();
    void animatingChanged();
    void aboutToComplete();
    void initializeItem(QQuickItem *item);
    void animate();
    void completeAnimation();
    void error(const QString &message);

protected:
    void componentComplete() override;

private:
    friend class KeelLoaderIncubator;
    void setStatus(Status status, const QString &errorString = QString());
    void startCreate();
    static QQmlComponent *cachedComponent(QQmlEngine *engine, const QUrl &url, bool asynchronous);
    void created(QObject *object);
    void failed(const QString &message);
    void clearReplaced();
    void cancelIncubation();
    void releaseIncubator();

    QVariant m_source;
    QPointer<QQuickItem> m_item;
    QPointer<QQuickItem> m_replaced;
    QPointer<QQmlComponent> m_component;
    // m_component was made from a URL (kept in the engine's cache).
    bool m_urlComponent = false;
    KeelLoaderIncubator *m_incubator = nullptr;
    QMetaObject::Connection m_componentConnection;
    QVariantMap m_properties;
    Status m_status = Null;
    QString m_errorString;
    bool m_asynchronous = false;
    bool m_animating = false;
    bool m_complete = false;
    bool m_loaded = false;
};

#endif // KEEL_ANIMATEDLOADER_H
