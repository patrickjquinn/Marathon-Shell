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

#ifndef NEMOTHUMBNAILITEM_H
#define NEMOTHUMBNAILITEM_H

#include <QtCore/qmutex.h>
#include <QtCore/qthread.h>
#include <QtCore/qwaitcondition.h>
#include <QQuickItem>
#include <QSGTexture>
#include <QBasicTimer>

#include "linkedlist.h"

struct ThumbnailRequest;

class NemoThumbnailLoader;
class NemoThumbnailItem : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(QUrl source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(QString mimeType READ mimeType WRITE setMimeType NOTIFY mimeTypeChanged)
    Q_PROPERTY(QSize sourceSize READ sourceSize WRITE setSourceSize NOTIFY sourceSizeChanged)
    Q_PROPERTY(FillMode fillMode READ fillMode WRITE setFillMode NOTIFY fillModeChanged)
    Q_PROPERTY(Priority priority READ priority WRITE setPriority NOTIFY priorityChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)
    Q_ENUMS(Priority)
    Q_ENUMS(Status)
    Q_ENUMS(FillMode)
public:
    enum FillMode {
        PreserveAspectFit = 1,  // Use the same values as Image for compatibility.
        PreserveAspectCrop
    };

    enum Priority {
        HighPriority,
        NormalPriority,
        LowPriority,
        Unprioritized
    };

    enum {
        PriorityCount = 3
    };

    enum Status {
        Null,
        Ready,
        Loading,
        Error
    };

    explicit NemoThumbnailItem(QQuickItem *parent = 0);
    ~NemoThumbnailItem();

    void componentComplete();

    QUrl source() const;
    void setSource(const QUrl &source);

    QString mimeType() const;
    void setMimeType(const QString &mimeType);

    QSize sourceSize() const;
    void setSourceSize(const QSize &size);

    FillMode fillMode() const;
    void setFillMode(FillMode mode);

    Priority priority() const;
    void setPriority(Priority priority);

    Status status() const;

    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *);
    void itemChange(ItemChange, const ItemChangeData &);

    static NemoThumbnailLoader *qmlAttachedProperties(QObject *);

    LinkedListNode listNode;

Q_SIGNALS:
    void sourceChanged();
    void mimeTypeChanged();
    void sourceSizeChanged();
    void fillModeChanged();
    void priorityChanged();
    void statusChanged();

private:
    Q_DISABLE_COPY(NemoThumbnailItem)

    void updateThumbnail(bool identityChanged);
    void timerEvent(QTimerEvent *event);
    void createLoader(QQuickWindow *window);

    NemoThumbnailLoader *m_loader;
    ThumbnailRequest *m_request;
    QUrl m_source;
    QString m_mimeType;
    QSize m_sourceSize;
    Priority m_priority;
    FillMode m_fillMode;
    bool m_imageChanged;
    QBasicTimer delayLoaderCreationTimer;

    friend struct ThumbnailRequest;
    friend class NemoThumbnailLoader;
};

QML_DECLARE_TYPE(NemoThumbnailItem)
QML_DECLARE_TYPEINFO(NemoThumbnailItem, QML_HAS_ATTACHED_PROPERTIES)

typedef LinkedList<NemoThumbnailItem, &NemoThumbnailItem::listNode> ThumbnailItemList;

struct ThumbnailRequest
{
    ThumbnailRequest(NemoThumbnailItem *item, const QString &fileName, uint cacheKey);
    ~ThumbnailRequest();

    LinkedListNode listNode;
    ThumbnailItemList items;
    uint cacheKey;
    QString fileName;
    QString mimeType;
    QSize size;
    QImage image;
    QImage pixmap;
    QSGTexture *texture;
    NemoThumbnailItem::FillMode fillMode;
    NemoThumbnailItem::Status status;
    NemoThumbnailItem::Priority priority;
    bool loading;
    bool loaded;
    uint cacheCost;
};

typedef LinkedList<ThumbnailRequest, &ThumbnailRequest::listNode> ThumbnailRequestList;

class NemoThumbnailLoader : public QThread
{
    Q_OBJECT
    Q_PROPERTY(int maxCost READ maxCost WRITE setMaxCost NOTIFY maxCostChanged)
public:
    explicit NemoThumbnailLoader(QQuickWindow *window);
    ~NemoThumbnailLoader();

    void updateRequest(NemoThumbnailItem *item, bool identityChanged);
    void cancelRequest(NemoThumbnailItem *item);
    void prioritizeRequest(ThumbnailRequest *request);

    static void shutdown();

    int maxCost() const;
    void setMaxCost(int cost);

signals:
    void maxCostChanged();

protected:
    bool event(QEvent *event);
    void run();

private:
    void restartLoader();
    void destroyTextures();

    ThumbnailRequestList m_thumbnailHighPriority;
    ThumbnailRequestList m_thumbnailNormalPriority;
    ThumbnailRequestList m_thumbnailLowPriority;
    ThumbnailRequestList m_generateHighPriority;
    ThumbnailRequestList m_generateNormalPriority;
    ThumbnailRequestList m_generateLowPriority;
    ThumbnailRequestList m_completedRequests;
    ThumbnailRequestList m_cachedRequests;
    QHash<uint, ThumbnailRequest *> m_requestCache;

    QMutex m_mutex;
    QWaitCondition m_waitCondition;
    QWindow *m_window;
    int m_totalCost;
    int m_maxCost;
    bool m_quit;
    bool m_suspend;
};

#endif
