// SPDX-FileCopyrightText: 2012 Jolla Ltd
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Jolla Ltd
 * Contact: Andrew den Exter <andrew.den.exter@jollamobile.com>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#include "nemothumbnailitem.h"

#include "nemothumbnailcache.h"

#include "linkedlist.h"

#include <QCoreApplication>

#include <QSGSimpleTextureNode>
#include <QQuickWindow>

namespace {

template <typename T, int N> int lengthOf(const T(&)[N]) { return N; }

int thumbnailerMaxCost()
{
    const QByteArray costEnv = qgetenv("NEMO_THUMBNAILER_CACHE_SIZE");

    bool ok = false;
    int cost = costEnv.toInt(&ok);
    return ok ? cost : 1360 * 768 * 3;
}

int MaximumSaneSize = 10000;
}

ThumbnailRequest::ThumbnailRequest(NemoThumbnailItem *item, const QString &fileName, uint cacheKey)
    : cacheKey(cacheKey)
    , fileName(fileName)
    , mimeType(item->m_mimeType)
    , size(item->m_sourceSize)
    , texture(0)
    , fillMode(item->m_fillMode)
    , status(NemoThumbnailItem::Loading)
    , priority(NemoThumbnailItem::Unprioritized)
    , loading(false)
    , loaded(false)
    , cacheCost(0)
{
}

ThumbnailRequest::~ThumbnailRequest()
{
    if (texture) {
        texture->deleteLater();
    }
}

/*!
    \qmltype Thumbnail
    \inqmlmodule Nemo.Thumbnailer
    \brief Generates and displays a cached thumbnail of the source image or video.

    Thumbnail element can be used instead of Qt Quick Image element for displaying
    images and video thumbnails. Thumbnailer provides additional API for prioritising
    requests and quering status of the thumbnail generation. Loaded thumbnails are
    stored into a local disk cache, which speeds up subsquent loading of the thumbnails,
    especially if the original source image or video was large.

    \code
    import QtQuick 2.0
    import Nemo.Thumbnailer 1.0

    Thumbnail {
        source: "photo.jpg"
        width: thumbnailWidth
        height: thumbnailHeight
        sourceSize.width: width
        sourceSize.height: height
        priority: {
            if (visibleRangeStart <= index && index < visibleRangeEnd) {
                return Thumbnail.HighPriority
            } else {
                return Thumbnail.LowPriority
            }
        }
    }
    \endcode
*/

NemoThumbnailItem::NemoThumbnailItem(QQuickItem *parent)
    : QQuickItem(parent)
    , m_loader(0)
    , m_request(0)
    , m_priority(NormalPriority)
    , m_fillMode(PreserveAspectCrop)
    , m_imageChanged(false)
{
    setFlag(QQuickItem::ItemHasContents, true);
}

NemoThumbnailItem::~NemoThumbnailItem()
{
    if (m_request)
        m_loader->cancelRequest(this);
}

void NemoThumbnailItem::componentComplete()
{
    QQuickItem::componentComplete();

    updateThumbnail(true);
}

/*!
    \qmlproperty url Thumbnail::source

    Set the location of the image to \a source property, either as an absolute or relative url.
*/
QUrl NemoThumbnailItem::source() const
{
    return m_source;
}

void NemoThumbnailItem::setSource(const QUrl &source)
{
    if (m_source != source) {
        m_source = source;
        emit sourceChanged();
        updateThumbnail(true);
    }
}

/*!
    \qmlproperty string Thumbnail::mimeType

    Mime type of the thumbnail, which helps the thumbnailer
    detect the file type correctly.
*/
QString NemoThumbnailItem::mimeType() const
{
    return m_mimeType;
}

void NemoThumbnailItem::setMimeType(const QString &mimeType)
{
    if (m_mimeType != mimeType) {
        m_mimeType = mimeType;
        emit mimeTypeChanged();
        updateThumbnail(!m_request);
    }
}

/*!
    \qmlproperty NemoThumbnailItem::Priority Thumbnail::priority.

    With priority system you can prioritise images currently visible
    on the screen higher. For example it is good idea to prioritise currently
    visible items when user is scrolling quickly through multiple large photos.

    The \a priority parameter may be one of:
    \list
    \li Thumbnail.HighPriority
    \li Thumbnail.NormalPriority
    \li Thumbnail.LowPriority
    \endlist
*/
NemoThumbnailItem::Priority NemoThumbnailItem::priority() const
{
    return m_priority;
}

void NemoThumbnailItem::setPriority(Priority priority)
{
    if (m_priority != priority) {
        m_priority = priority;
        emit priorityChanged();
        if (m_request)
            m_loader->updateRequest(this, false);
    }
}

/*!
    \qmlproperty QSize Thumbnail::sourceSize

    This property holds the actual width and height of the cached and displayed thumbnail.
    The source size should always be defined.
*/
QSize NemoThumbnailItem::sourceSize() const
{
    return m_sourceSize;
}

void NemoThumbnailItem::setSourceSize(const QSize &size)
{
    if (m_sourceSize != size) {
        m_sourceSize = size;
        emit sourceSizeChanged();
        updateThumbnail(true);
    }
}

/*!
    \qmlproperty enumeration Thumbnail::fillMode

    Set this property to define what happens when the source image
    has a different aspect ratio than the item.

    \list
    \li Thumbnail.PreserveAspectFit - the image is scaled uniformly to fit without cropping
    \li Thumbnail.PreserveAspectCrop - the image is scaled uniformly to fill, cropping if necessary. This is the default behavior.
    \endlist
*/
NemoThumbnailItem::FillMode NemoThumbnailItem::fillMode() const
{
    return m_fillMode;
}

void NemoThumbnailItem::setFillMode(FillMode mode)
{
    if (m_fillMode != mode) {
        m_fillMode = mode;
        emit fillModeChanged();
        updateThumbnail(true);
    }
}

/*!
    \qmlproperty enumeration Thumbnail::status

    This property holds the status of the thumbnail loading. It can be one of:
    \list
    \li Thumbnail.Null - no image has been set
    \li Thumbnail.Ready - the thumbnail has been loaded
    \li Thumbnail.Loading - the thumbnail is currently being loaded
    \li Thumbnail.Error - an error occurred while generating the thumbnail
    \endlist
*/
NemoThumbnailItem::Status NemoThumbnailItem::status() const
{
    return m_request ? m_request->status : Null;
}

QSGNode *NemoThumbnailItem::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    QSGSimpleTextureNode *node = static_cast<QSGSimpleTextureNode *>(oldNode);
    if (!m_request || (m_request->pixmap.isNull() && !m_request->texture)) {
        delete node;
        return 0;
    }

    if (!node)
        node = new QSGSimpleTextureNode;

    if (!m_request->pixmap.isNull()) {
        delete m_request->texture;
        m_request->texture = window()->createTextureFromImage(m_request->pixmap, QQuickWindow::TextureCanUseAtlas);
        m_request->pixmap = QImage();
    }

    if (m_imageChanged || !node->texture()) {
        m_imageChanged = false;
        node->setTexture(m_request->texture);
    }

    QRectF rect(QPointF(0, 0), m_request->texture->textureSize().scaled(
                width(),
                height(),
                m_fillMode == PreserveAspectFit ? Qt::KeepAspectRatio : Qt::KeepAspectRatioByExpanding));
    rect.moveCenter(QPointF(width() / 2, height() / 2));
    node->setRect(rect);

    return node;
}

void NemoThumbnailItem::updateThumbnail(bool identityChanged)
{
    if (!isComponentComplete() || !m_loader)
        return;

    Status status = m_request ? m_request->status : Null;

    bool valid = m_source.isLocalFile() && !m_sourceSize.isEmpty();
    if (valid && (m_sourceSize.width() > MaximumSaneSize || m_sourceSize.height() > MaximumSaneSize)) {
        qDebug() << "Thumbnail source size too big, ignoring update. Size:" << m_sourceSize;
        valid = false;
    }

    if (valid)
        m_loader->updateRequest(this, identityChanged);
    else if (m_request)
        m_loader->cancelRequest(this);

    if (status != (m_request ? m_request->status : Null))
        emit statusChanged();
}

void NemoThumbnailItem::itemChange(ItemChange change, const ItemChangeData &data)
{
    if (change == ItemSceneChange) {
        if (m_request) {
            m_loader->cancelRequest(this);
            m_request = 0;
        }

        createLoader(data.window);
        if (!m_loader) {
            // Work-around QTBUG-57396 by delaying qmlAttachedPropertiesObject call
            delayLoaderCreationTimer.start(0, this);
        }
    }
    QQuickItem::itemChange(change, data);
}

void NemoThumbnailItem::timerEvent(QTimerEvent* event)
{
    if (event && event->timerId() == delayLoaderCreationTimer.timerId()) {
        delayLoaderCreationTimer.stop();
        createLoader(window());
    }
}

void NemoThumbnailItem::createLoader(QQuickWindow *window)
{
    if (!m_loader) {
        m_loader = window
                ? qobject_cast<NemoThumbnailLoader *>(qmlAttachedPropertiesObject<NemoThumbnailItem>(window))
                : 0;
        updateThumbnail(true);
    }
}

NemoThumbnailLoader *NemoThumbnailItem::qmlAttachedProperties(QObject *object)
{
    if (QQuickWindow *window = qobject_cast<QQuickWindow *>(object)) {
        return new NemoThumbnailLoader(window);
    } else {
        return 0;
    }
}


NemoThumbnailLoader::NemoThumbnailLoader(QQuickWindow *window)
    : QThread(window)
    , m_window(window)
    , m_totalCost(0)
    , m_maxCost(thumbnailerMaxCost())
    , m_quit(false)
    , m_suspend(false)
{
    connect(window, &QQuickWindow::sceneGraphInitialized,
                this, &NemoThumbnailLoader::restartLoader,
                Qt::DirectConnection);
    connect(window, &QQuickWindow::sceneGraphInvalidated,
                this, &NemoThumbnailLoader::destroyTextures,
                Qt::DirectConnection);
}

NemoThumbnailLoader::~NemoThumbnailLoader()
{
    {
        QMutexLocker locker(&m_mutex);

        m_quit = true;
        m_waitCondition.wakeOne();
    }

    wait();

    ThumbnailRequestList *lists[] = {
        &m_thumbnailHighPriority,
        &m_thumbnailNormalPriority,
        &m_thumbnailLowPriority,
        &m_generateHighPriority,
        &m_generateNormalPriority,
        &m_generateLowPriority,
        &m_completedRequests,
        &m_cachedRequests
    };

    for (int i = 0; i < lengthOf(lists); ++i) {
        while (ThumbnailRequest *request = lists[i]->takeFirst())
            delete request;
    }
}

int NemoThumbnailLoader::maxCost() const
{
    return m_maxCost;
}

void NemoThumbnailLoader::setMaxCost(int cost)
{
    if (m_maxCost != cost) {
        m_maxCost = cost;
        emit maxCostChanged();
    }
}

void NemoThumbnailLoader::updateRequest(NemoThumbnailItem *item, bool identityChanged)
{
    ThumbnailRequest *previousRequest = item->m_request;
    // If any property that forms part of the cacheKey has changed, create a new request or
    // attach to an existing request for the same cacheKey.
    if (identityChanged) {
        const bool wasReady = item->m_request && item->m_request->status == NemoThumbnailItem::Ready;
        item->listNode.erase();

        const QString fileName = item->m_source.toLocalFile();
        const bool crop = item->m_fillMode == NemoThumbnailItem::PreserveAspectCrop;

        // Create an identifier for this request's data
        const uint cacheKey = qHash(crop)
                ^ qHash(item->m_sourceSize.width())
                ^ qHash(item->m_sourceSize.height())
                ^ qHash(fileName);

        item->m_request = m_requestCache.value(cacheKey);

        if (!item->m_request) {
            item->m_request = new ThumbnailRequest(item, fileName, cacheKey);
            m_requestCache.insert(cacheKey, item->m_request);
        }
        item->m_request->items.append(item);

        // If an existing request is already completed, push it to the back of the cached requests
        // lists to renew it and update the item.
        if (item->m_request->status == NemoThumbnailItem::Ready) {
            m_cachedRequests.append(item->m_request);

            item->m_imageChanged = true;
            item->setImplicitWidth(item->m_request->pixmap.width());
            item->setImplicitHeight(item->m_request->pixmap.height());
            emit item->statusChanged();
            item->update();
            return;
        } else if (wasReady) {
            item->update();
        }
    }

    // If the cache is full release excess unreferenced items.
    ThumbnailRequestList::iterator it = m_cachedRequests.begin();
    while (m_totalCost > m_maxCost && it != m_cachedRequests.end()) {
        if (it->items.isEmpty()) {
            ThumbnailRequest *cachedRequest = it;
            it = m_cachedRequests.erase(it);
            m_totalCost -= cachedRequest->cacheCost;
            m_requestCache.remove(cachedRequest->cacheKey);

            if (cachedRequest == previousRequest) {
                // Avoid dangling pointer if previous request is purged from cache
                previousRequest = nullptr;
            }

            delete cachedRequest;
        } else {
            ++it;
        }
    }

    QMutexLocker locker(&m_mutex);

    // If the item's existing request was replaced, destroy or reprioritize if it is referenced
    // by other items.
    if (previousRequest != item->m_request && previousRequest)
        prioritizeRequest(previousRequest);

    prioritizeRequest(item->m_request);

    m_waitCondition.wakeOne();

    start();
}

void NemoThumbnailLoader::cancelRequest(NemoThumbnailItem *item)
{
    ThumbnailRequest *request = item->m_request;
    Q_ASSERT(request);

    if (request->status == NemoThumbnailItem::Ready)
        item->update();

    // Remove the item from the request list.
    item->listNode.erase();
    item->m_request = 0;

    // Destroy or reprioritize the request as appropriate.
    QMutexLocker locker(&m_mutex);
    prioritizeRequest(request);
}

void NemoThumbnailLoader::prioritizeRequest(ThumbnailRequest *request)
{
    if (request->loaded)
        return;

    ThumbnailRequestList *lists[] = {
        &m_thumbnailHighPriority, &m_thumbnailNormalPriority, &m_thumbnailLowPriority
    };

    NemoThumbnailItem::Priority priority = NemoThumbnailItem::LowPriority;
    for (ThumbnailItemList::iterator it = request->items.begin(); it !=  request->items.end(); ++it)
        priority = qMin(priority, it->m_priority);

    if (request->items.isEmpty()) {
        // Cancel a pending request with no target items unless it's currently being loaded in
        // which case let it complete as it will either just be cached or appended to the low
        // priority generate queue.
        if (!request->loading) {
            m_requestCache.remove(request->cacheKey);
            delete request;
        }
    } else if (request->priority != priority) {
        request->priority = priority;
        if (!request->loading)
            lists[priority]->append(request);
    }
}

bool NemoThumbnailLoader::event(QEvent *event)
{
    if (event->type() == QEvent::User) {
        // Move items from the completedRequests list to cachedRequests.
        ThumbnailRequestList completedRequests;
        {
            QMutexLocker locker(&m_mutex);
            completedRequests = m_completedRequests;
        }

        while (ThumbnailRequest *request = completedRequests.takeFirst()) {
            m_cachedRequests.append(request);

            // Update any items associated with the request.
            const QSize implicitSize = request->image.size();
            if (!request->image.isNull()) {
                request->pixmap = request->image;
                request->image = QImage();
                request->status = NemoThumbnailItem::Ready;

                // Store the cache cost associated with request as pixmap may get freed
                // if it is loaded into texture
                request->cacheCost = implicitSize.width() * implicitSize.height();
                m_totalCost += request->cacheCost;
            } else {
                request->pixmap = QImage();
                request->image = QImage();

                request->status = NemoThumbnailItem::Error;
            }
            for (ThumbnailItemList::iterator item = request->items.begin();
                    item != request->items.end();
                    ++item) {
                item->m_imageChanged = true;
                item->setImplicitWidth(implicitSize.width());
                item->setImplicitHeight(implicitSize.height());
                emit item->statusChanged();
                item->update();
            }
        }

        return true;
    } else {
        return QThread::event(event);
    }
}

void NemoThumbnailLoader::run()
{
    QMutexLocker locker(&m_mutex);

    for (;;) {
        ThumbnailRequest *request = 0;
        bool tryCache;

        // Grab the next request in priority order.  High and normal priority thumbnails are
        // prioritized over generating any thumbnail, and low priority loading or generation
        // is deprioritized over everything else.
        if (m_quit) {
            return;
        } else if (m_suspend) {
            m_waitCondition.wait(&m_mutex);
            continue;
        } else if ((request = m_thumbnailHighPriority.takeFirst())
                || (request = m_thumbnailNormalPriority.takeFirst())) {
            tryCache = true;
        } else if ((request = m_generateHighPriority.takeFirst())
                || (request = m_generateNormalPriority.takeFirst())) {
            tryCache = false;
        } else if ((request = m_thumbnailLowPriority.takeFirst())) {
            tryCache = true;
        } else if ((request = m_generateLowPriority.takeFirst())) {
            tryCache = false;
        } else {
            m_waitCondition.wait(&m_mutex);
            continue;
        }

        Q_ASSERT(request);
        const QString fileName = request->fileName;
        const QString mimeType = request->mimeType;
        const QSize requestedSize = request->size;
        const bool crop = request->fillMode == NemoThumbnailItem::PreserveAspectCrop;

        request->loading = true;

        locker.unlock();

        if (tryCache) {
            NemoThumbnailCache::ThumbnailData thumbnail
                    = NemoThumbnailCache::instance()->existingThumbnail(fileName, requestedSize, crop);
            QImage image = thumbnail.getScaledImage(requestedSize, crop);

            locker.relock();
            request->loading = false;

            if (!image.isNull()) {
                request->loaded = true;
                request->image = image;
                if (m_completedRequests.isEmpty())
                    QCoreApplication::postEvent(this, new QEvent(QEvent::User));
                m_completedRequests.append(request);
            } else {
                ThumbnailRequestList *lists[] = {
                    &m_generateHighPriority, &m_generateNormalPriority, &m_generateLowPriority
                };
                lists[request->priority]->append(request);
            }
        } else {
            NemoThumbnailCache::ThumbnailData thumbnail
                    = NemoThumbnailCache::instance()->requestThumbnail(fileName, requestedSize, crop, true, mimeType);
            QImage image = thumbnail.getScaledImage(requestedSize, crop);

            locker.relock();
            request->loading = false;
            request->loaded = true;
            request->image = image;
            if (m_completedRequests.isEmpty())
                QCoreApplication::postEvent(this, new QEvent(QEvent::User));
            m_completedRequests.append(request);
        }
    }
}

void NemoThumbnailLoader::restartLoader()
{
    {
        QMutexLocker locker(&m_mutex);
        m_suspend = false;
        m_waitCondition.wakeOne();
    }
}

void NemoThumbnailLoader::destroyTextures()
{
    QList<QSGTexture *> textures;
    QList<NemoThumbnailItem *> invalidatedItems;

    {
        QMutexLocker locker(&m_mutex);

        m_suspend = true;

        ThumbnailRequestList *lists[] = {
            &m_thumbnailHighPriority,
            &m_thumbnailNormalPriority,
            &m_thumbnailLowPriority,
            &m_generateHighPriority,
            &m_generateNormalPriority,
            &m_generateLowPriority,
            &m_completedRequests
        };

        for (int i = 0; i < lengthOf(lists); ++i) {
            for (ThumbnailRequestList::iterator request = lists[i]->begin();
                        request != lists[i]->end();
                        ++request) {
                if (request->texture) {
                    textures.append(request->texture);
                    request->texture = 0;
                }
            }
        }

        ThumbnailRequestList cachedRequests = m_cachedRequests;
        while (ThumbnailRequest *request = cachedRequests.takeFirst()) {
            if (request->texture) {
                for (ThumbnailItemList::iterator item = request->items.begin();
                            item != request->items.end();
                            ++item) {
                    invalidatedItems.append(item);
                }
                textures.append(request->texture);
                request->texture = 0;
                request->loaded = false;
                request->status = NemoThumbnailItem::Loading;
                lists[request->priority]->append(request);
            } else {
                m_cachedRequests.append(request);
            }
        }
    }

    qDeleteAll(textures);
    foreach (NemoThumbnailItem *item, invalidatedItems) {
        emit item->statusChanged();
    }
}
