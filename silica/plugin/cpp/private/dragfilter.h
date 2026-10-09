// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// DragFilter (Sailfish.Silica.private), attached to a pressable item. API
// inferred from Silica's BSD QML (BackgroundItem, Button, Switch, TextSwitch,
// SliderBase): begin(x, y) on press, end() on cancel, `canceled`,
// `screenMargin`, `orientations`. Clean-room behaviour: between begin() and
// the release, a pointer movement beyond the start-drag distance along one
// of `orientations` (default horizontal and vertical) cancels the press
// feedback (`canceled` becomes true), so that a press that turns into a
// page swipe or a scroll does not stay highlighted. Presses that start
// within `screenMargin` of the left or right window edge cancel at half that
// distance (edge swipes). The release ends the filter.
#ifndef KEEL_DRAGFILTER_H
#define KEEL_DRAGFILTER_H

#include <QObject>
#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

class KeelDragFilterAttached : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool canceled READ canceled NOTIFY canceledChanged)
    Q_PROPERTY(qreal screenMargin READ screenMargin WRITE setScreenMargin NOTIFY screenMarginChanged)
    Q_PROPERTY(int orientations READ orientations WRITE setOrientations NOTIFY orientationsChanged)

public:
    explicit KeelDragFilterAttached(QObject *attachee);

    bool canceled() const { return m_canceled; }
    qreal screenMargin() const { return m_screenMargin; }
    void setScreenMargin(qreal margin);
    int orientations() const { return m_orientations; }
    void setOrientations(int orientations);

    Q_INVOKABLE void begin(qreal x, qreal y);
    Q_INVOKABLE void end();

signals:
    void canceledChanged();
    void screenMarginChanged();
    void orientationsChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void setCanceled(bool canceled);
    void move(const QPointF &scenePos);

    QPointer<QQuickItem> m_item;
    QPointer<QQuickWindow> m_window;
    QPointF m_start;
    bool m_active = false;
    bool m_edge = false;
    bool m_canceled = false;
    qreal m_screenMargin = 0;
    int m_orientations = Qt::Horizontal | Qt::Vertical;
};

class KeelDragFilter : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(DragFilter)
    QML_UNCREATABLE("DragFilter is an attached property")
    QML_ATTACHED(KeelDragFilterAttached)

public:
    static KeelDragFilterAttached *qmlAttachedProperties(QObject *object)
    {
        return new KeelDragFilterAttached(object);
    }
};

#endif // KEEL_DRAGFILTER_H
