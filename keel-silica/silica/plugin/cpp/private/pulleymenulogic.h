// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PulleyMenuLogic (Sailfish.Silica.private): the native half of Silica's BSD
// PulleyMenuBase.qml. API inferred from that file: `flickable`,
// `pullDownType`, `dragDistance`, monitorFlick(), outOfBounds(),
// finalPositionReached(), animateFlick(duration, position). BounceEffect
// (private/BoundsBehavior.qml): `flickable`, `active`, `difference`.
// Clean-room behaviour. The logic is a child of its menu (PulleyMenuBase)
// and reads the menu's _inactivePosition, _finalPosition and
// _activationPermitted:
//  - dragDistance: how far the flickable is past the menu's inactive
//    position towards the menu (0 when not);
//  - the menu becomes `active` when the user drags past the inactive
//    position with activation permitted at the start of the drag, and
//    inactive again when the flickable is back at the inactive position and
//    no longer moving;
//  - finalPositionReached() when a drag reaches the menu's final position;
//  - outOfBounds(): the flickable is beyond the final position;
//  - monitorFlick(): a flick that would carry an inactive menu's flickable
//    past the inactive position is stopped there with animateFlick().
// BounceEffect, clean-room: for a view that stops at its bounds, `difference`
// is how far the pointer has been dragged on past the bound the view rests
// at; `active` while it is positive.
#ifndef KEEL_PULLEYMENULOGIC_H
#define KEEL_PULLEYMENULOGIC_H

#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QQmlListProperty>
#include <QtQml/qqmlregistration.h>

class KeelPulleyMenuLogic : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PulleyMenuLogic)
    Q_PROPERTY(QQuickItem *flickable READ flickable WRITE setFlickable NOTIFY flickableChanged)
    Q_PROPERTY(bool pullDownType READ pullDownType WRITE setPullDownType NOTIFY pullDownTypeChanged)
    Q_PROPERTY(qreal dragDistance READ dragDistance NOTIFY dragDistanceChanged)

public:
    explicit KeelPulleyMenuLogic(QObject *parent = nullptr);

    QQuickItem *flickable() const { return m_flickable; }
    void setFlickable(QQuickItem *flickable);
    bool pullDownType() const { return m_pullDown; }
    void setPullDownType(bool pullDown);
    qreal dragDistance() const { return m_dragDistance; }

    Q_INVOKABLE void monitorFlick();
    Q_INVOKABLE bool outOfBounds() const;

signals:
    void flickableChanged();
    void pullDownTypeChanged();
    void dragDistanceChanged();
    void finalPositionReached();
    void animateFlick(qreal duration, qreal position);

private slots:
    void update();
    void draggingChanged();

private:
    QObject *menu() const { return parent(); }
    qreal menuReal(const char *name) const;
    qreal contentY() const;
    void setActive(bool active);

    QPointer<QQuickItem> m_flickable;
    QList<QMetaObject::Connection> m_connections;
    bool m_pullDown = true;
    bool m_permitted = false;
    bool m_atFinal = false;
    qreal m_dragDistance = 0;
};

class KeelBounceEffect : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(BounceEffect)
    Q_CLASSINFO("DefaultProperty", "data")
    Q_PROPERTY(QQmlListProperty<QObject> data READ data CONSTANT)
    Q_PROPERTY(QQuickItem *flickable READ flickable WRITE setFlickable NOTIFY flickableChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    Q_PROPERTY(qreal difference READ difference NOTIFY differenceChanged)

public:
    explicit KeelBounceEffect(QObject *parent = nullptr);
    ~KeelBounceEffect() override;

    QQuickItem *flickable() const { return m_flickable; }
    void setFlickable(QQuickItem *flickable);
    bool active() const { return m_difference > 0; }
    qreal difference() const { return m_difference; }
    QQmlListProperty<QObject> data() { return QQmlListProperty<QObject>(this, &m_data); }

signals:
    void flickableChanged();
    void activeChanged();
    void differenceChanged();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void watchWindow();
    void setDifference(qreal difference);
    void track(const QPointF &scenePos);

    QPointer<QQuickItem> m_flickable;
    QPointer<QQuickWindow> m_window;
    bool m_pressed = false;
    bool m_hasEdge = false;
    qreal m_edgeY = 0;
    int m_edge = 0; // -1 at the beginning, 1 at the end
    qreal m_difference = 0;
    QList<QObject *> m_data;
};

#endif // KEEL_PULLEYMENULOGIC_H
