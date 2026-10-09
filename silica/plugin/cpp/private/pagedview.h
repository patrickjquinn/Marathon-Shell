// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PagedViewBase (Sailfish.Silica.private): the native part of Keel's
// PagedView (qml/PagedView.qml), which is Silica's PagedView rebuilt from its
// public documentation ("PagedView QML Type") and from how Silica's BSD QML
// uses it (private/TabView.qml, private/TabItem.qml). Clean-room: Silica's
// PagedView is native and closed.
//
// QML cannot declare attached properties, so this base type carries them:
// PagedView.view, PagedView.contentWidth and PagedView.contentHeight (the
// documented ones) and PagedView.isCurrentItem and PagedView.exposed (the
// ones Silica's TabView and TabItem read). The view's QML sets each page's
// state with _keelUpdate(); an item that is not (yet) a page finds the view
// among its ancestors for view, contentWidth and contentHeight.
#ifndef KEEL_PAGEDVIEW_H
#define KEEL_PAGEDVIEW_H

#include <QPointer>
#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class KeelPagedViewBase;

class KeelPagedViewAttached : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuickItem *view READ view NOTIFY viewChanged)
    Q_PROPERTY(qreal contentWidth READ contentWidth NOTIFY contentSizeChanged)
    Q_PROPERTY(qreal contentHeight READ contentHeight NOTIFY contentSizeChanged)
    Q_PROPERTY(bool isCurrentItem READ isCurrentItem NOTIFY isCurrentItemChanged)
    Q_PROPERTY(bool exposed READ exposed NOTIFY exposedChanged)

public:
    explicit KeelPagedViewAttached(QObject *attachee);

    QQuickItem *view() const;
    qreal contentWidth() const;
    qreal contentHeight() const;
    bool isCurrentItem() const { return m_current; }
    bool exposed() const { return m_exposed; }

    void setView(KeelPagedViewBase *view);
    void setState(bool current, bool exposed);

signals:
    void viewChanged();
    void contentSizeChanged();
    void isCurrentItemChanged();
    void exposedChanged();

private:
    void findView();

    QPointer<QQuickItem> m_item;
    QPointer<KeelPagedViewBase> m_view;
    bool m_explicit = false;
    bool m_current = false;
    bool m_exposed = false;
};

class KeelPagedViewBase : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PagedViewBase)
    QML_ATTACHED(KeelPagedViewAttached)
    // The size of the view's contentItem (PagedView.contentWidth/Height).
    Q_PROPERTY(qreal _keelContentWidth READ contentWidth WRITE setContentWidth NOTIFY contentSizeChanged)
    Q_PROPERTY(qreal _keelContentHeight READ contentHeight WRITE setContentHeight NOTIFY contentSizeChanged)

public:
    explicit KeelPagedViewBase(QQuickItem *parent = nullptr);

    static KeelPagedViewAttached *qmlAttachedProperties(QObject *object);

    qreal contentWidth() const { return m_contentWidth; }
    void setContentWidth(qreal width);
    qreal contentHeight() const { return m_contentHeight; }
    void setContentHeight(qreal height);

    // A page's attached state.
    Q_INVOKABLE void _keelUpdate(QQuickItem *item, bool current, bool exposed);

signals:
    void contentSizeChanged();

private:
    qreal m_contentWidth = 0;
    qreal m_contentHeight = 0;
};

#endif // KEEL_PAGEDVIEW_H
