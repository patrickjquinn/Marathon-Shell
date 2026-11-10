// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see animatedloader.h.

#include "animatedloader.h"

#include <QHash>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlProperty>

void KeelLoaderIncubator::setInitialState(QObject *object)
{
    if (auto *item = qobject_cast<QQuickItem *>(object))
        item->setParentItem(m_loader);
    object->setParent(m_loader);
    for (auto it = m_loader->m_properties.cbegin(); it != m_loader->m_properties.cend(); ++it) {
        QQmlProperty prop(object, it.key());
        if (prop.isValid() && prop.isWritable())
            prop.write(it.value());
    }
    if (auto *item = qobject_cast<QQuickItem *>(object))
        emit m_loader->initializeItem(item);
}

void KeelLoaderIncubator::statusChanged(Status status)
{
    if (status == Ready)
        m_loader->created(object());
    else if (status == Error) {
        QString message;
        for (const QQmlError &e : errors())
            message += e.toString() + QLatin1Char('\n');
        m_loader->failed(message.trimmed());
    }
}

KeelAnimatedLoader::KeelAnimatedLoader(QQuickItem *parent)
    : QQuickItem(parent)
{
}

KeelAnimatedLoader::~KeelAnimatedLoader()
{
    cancelIncubation();
}

void KeelAnimatedLoader::setAsynchronous(bool a)
{
    if (a == m_asynchronous)
        return;
    m_asynchronous = a;
    emit asynchronousChanged();
}

void KeelAnimatedLoader::setAnimating(bool a)
{
    if (a == m_animating)
        return;
    m_animating = a;
    emit animatingChanged();
    if (!m_animating)
        clearReplaced();
}

void KeelAnimatedLoader::setStatus(Status status, const QString &errorString)
{
    if (status == m_status && errorString == m_errorString)
        return;
    m_status = status;
    m_errorString = errorString;
    emit statusChanged();
}

void KeelAnimatedLoader::componentComplete()
{
    QQuickItem::componentComplete();
    emit aboutToComplete();
    m_complete = true;
    if (!m_loaded && m_source.isValid() && !m_source.isNull())
        load(m_source, QVariant(), m_properties);
}

void KeelAnimatedLoader::setSource(const QVariant &source)
{
    if (source == m_source && m_loaded)
        return;
    if (!m_complete) {
        m_source = source;
        emit sourceChanged();
        return;
    }
    load(source, QVariant(), QVariantMap());
}

void KeelAnimatedLoader::cancelIncubation()
{
    if (m_incubator) {
        m_incubator->clear();
        delete m_incubator;
        m_incubator = nullptr;
    }
}

void KeelAnimatedLoader::clearReplaced()
{
    if (!m_replaced)
        return;
    QQuickItem *old = m_replaced;
    m_replaced = nullptr;
    emit replacedItemChanged();
    old->setParentItem(nullptr);
    old->setVisible(false);
    old->deleteLater();
}

namespace {

// The components AnimatedLoaders made from URLs, per engine (a child of the
// engine, so gone with it). One that failed is not kept.
class KeelLoaderComponentCache : public QObject
{
public:
    QHash<QUrl, QPointer<QQmlComponent>> components;
};

} // namespace

QQmlComponent *KeelAnimatedLoader::cachedComponent(QQmlEngine *engine, const QUrl &url, bool asynchronous)
{
    static QHash<QQmlEngine *, KeelLoaderComponentCache *> caches;
    KeelLoaderComponentCache *&cache = caches[engine];
    if (!cache) {
        cache = new KeelLoaderComponentCache;
        cache->setParent(engine);
        QObject::connect(engine, &QObject::destroyed, [engine] { caches.remove(engine); });
    }
    QPointer<QQmlComponent> &component = cache->components[url];
    if (component && component->isError()) {
        component->deleteLater();
        component = nullptr;
    }
    if (!component)
        component = new QQmlComponent(engine, url,
                                      asynchronous ? QQmlComponent::Asynchronous : QQmlComponent::PreferSynchronous,
                                      cache);
    return component;
}

void KeelAnimatedLoader::load(const QVariant &source, const QVariant &cacheKey, const QVariantMap &properties)
{
    Q_UNUSED(cacheKey)
    if (m_animating)
        emit completeAnimation();
    cancelIncubation();
    // A load of a component that is still loading is superseded.
    disconnect(m_componentConnection);
    const bool sourceChange = source != m_source;
    m_source = source;
    m_properties = properties;
    m_loaded = true;
    if (sourceChange)
        emit sourceChanged();

    m_component = nullptr;
    m_urlComponent = false;

    auto *obj = source.value<QObject *>();
    if (auto *component = qobject_cast<QQmlComponent *>(obj)) {
        m_component = component;
    } else if (!source.isValid() || source.isNull()
               || (source.metaType().id() == QMetaType::QString && source.toString().isEmpty())) {
        // Unload: the current item animates out.
        if (m_item) {
            clearReplaced();
            m_replaced = m_item;
            m_item = nullptr;
            emit itemChanged();
            emit replacedItemChanged();
            setStatus(Null);
            emit animate();
            if (!m_animating)
                clearReplaced();
        } else {
            setStatus(Null);
        }
        return;
    } else {
        QUrl url = source.toUrl();
        if (!url.isValid() || url.isEmpty())
            url = QUrl(source.toString());
        QQmlContext *context = qmlContext(this);
        if (context)
            url = context->resolvedUrl(url);
        QQmlEngine *engine = qmlEngine(this);
        if (!engine) {
            failed(QStringLiteral("AnimatedLoader: no QML engine"));
            return;
        }
        m_component = cachedComponent(engine, url, m_asynchronous);
        m_urlComponent = true;
    }

    setStatus(Loading);
    if (m_component->isLoading()) {
        if (!m_asynchronous)
            qWarning().noquote() << "AnimatedLoader:" << m_source.toString()
                                 << "is still loading; the item is created when it has loaded";
        m_componentConnection = connect(m_component, &QQmlComponent::statusChanged, this,
                                        [this, c = m_component.data()]() {
                                            if (c != m_component || c->isLoading())
                                                return;
                                            disconnect(m_componentConnection);
                                            startCreate();
                                        });
        return;
    }
    startCreate();
}

void KeelAnimatedLoader::startCreate()
{
    if (!m_component)
        return;
    if (m_component->isError()) {
        failed(m_component->errorString());
        return;
    }
    QQmlContext *context = m_component->creationContext();
    if (!context || m_urlComponent)
        context = qmlContext(this);
    m_incubator = new KeelLoaderIncubator(this, m_asynchronous ? QQmlIncubator::Asynchronous
                                                                : QQmlIncubator::Synchronous);
    m_component->create(*m_incubator, context);
}

void KeelAnimatedLoader::created(QObject *object)
{
    auto *item = qobject_cast<QQuickItem *>(object);
    releaseIncubator();
    if (!item) {
        delete object;
        failed(QStringLiteral("AnimatedLoader: the component did not create an Item"));
        return;
    }
    clearReplaced();
    m_replaced = m_item;
    m_item = item;
    emit itemChanged();
    if (m_replaced)
        emit replacedItemChanged();
    setStatus(Ready);
    emit animate();
    if (!m_animating)
        clearReplaced();
}

void KeelAnimatedLoader::releaseIncubator()
{
    // Called from the incubator's own status callback: delete it later. A
    // finished incubator no longer owns its object.
    if (KeelLoaderIncubator *inc = m_incubator) {
        m_incubator = nullptr;
        QMetaObject::invokeMethod(this, [inc] { delete inc; }, Qt::QueuedConnection);
    }
}

void KeelAnimatedLoader::failed(const QString &message)
{
    // Said out loud, as Qt's Loader does: a page that cannot be created is
    // otherwise only a null page further on.
    qWarning().noquote() << "AnimatedLoader:" << m_source.toString() << message;
    releaseIncubator();
    setStatus(Error, message);
    emit error(message);
}
