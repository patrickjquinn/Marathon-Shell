// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PageStackGestureArea (Sailfish.Silica.private, Keel's own name): the
// native half of PageStackBase, the base of Silica's BSD PageStack.qml.
// The properties are those PageStack.qml reads from its base: `pressed`,
// pressed()/released()/canceled(), the drag distances
// `_leftFlickDifference`, `_rightFlickDifference`, `_upFlickDifference`,
// `_downFlickDifference`, `backNavigation`, `forwardNavigation`,
// `navigationStyle` (PageNavigation.Horizontal 0 / Vertical 1),
// `horizontalNavigationStyle`, and resolveImportPage().
//
// Clean-room behaviour: the area watches the pointer events of its
// children (pages). A drag that passes the start-drag distance along the
// navigation axis, in a direction the current page can navigate (to the
// right or down: back; to the left: forward), is taken over: `pressed`
// becomes true and pressed() is emitted, the child that had the press is
// cancelled, and the distances follow the pointer:
// _leftFlickDifference is how far right of the press point it is,
// _rightFlickDifference how far left, _upFlickDifference how far below,
// _downFlickDifference how far above (in the area's own coordinates, so
// they follow the page orientation). On release released() is emitted
// with the distances still set; they return to 0 afterwards. A child that
// keeps its grab (MouseArea.preventStealing) is not interrupted. Mouse and
// touch alike: on a phone the pages' flickables get touch events, and the
// area takes over the touch point itself (grabbing "the mouse" there took
// nothing, so the drag never ended and the page stack stayed half dragged).
#ifndef KEEL_PAGESTACKGESTURE_H
#define KEEL_PAGESTACKGESTURE_H

#include <QPointF>
#include <QQuickItem>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class KeelPageStackGestureArea : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PageStackGestureArea)
    Q_PROPERTY(bool pressed READ isPressed NOTIFY pressedChanged)
    Q_PROPERTY(bool backNavigation READ backNavigation WRITE setBackNavigation NOTIFY backNavigationChanged)
    Q_PROPERTY(bool forwardNavigation READ forwardNavigation WRITE setForwardNavigation NOTIFY forwardNavigationChanged)
    Q_PROPERTY(int navigationStyle READ navigationStyle WRITE setNavigationStyle NOTIFY navigationStyleChanged)
    Q_PROPERTY(bool horizontalNavigationStyle READ horizontalNavigationStyle NOTIFY navigationStyleChanged)
    Q_PROPERTY(qreal _leftFlickDifference READ leftDifference NOTIFY differencesChanged)
    Q_PROPERTY(qreal _rightFlickDifference READ rightDifference NOTIFY differencesChanged)
    Q_PROPERTY(qreal _upFlickDifference READ upDifference NOTIFY differencesChanged)
    Q_PROPERTY(qreal _downFlickDifference READ downDifference NOTIFY differencesChanged)

public:
    explicit KeelPageStackGestureArea(QQuickItem *parent = nullptr);

    bool isPressed() const { return m_pressed; }
    bool backNavigation() const { return m_back; }
    void setBackNavigation(bool b);
    bool forwardNavigation() const { return m_forward; }
    void setForwardNavigation(bool f);
    int navigationStyle() const { return m_style; }
    void setNavigationStyle(int style);
    bool horizontalNavigationStyle() const { return m_style == 0; }
    qreal leftDifference() const { return qMax<qreal>(0, m_delta.x()); }
    qreal rightDifference() const { return qMax<qreal>(0, -m_delta.x()); }
    qreal upDifference() const { return qMax<qreal>(0, m_delta.y()); }
    qreal downDifference() const { return qMax<qreal>(0, -m_delta.y()); }

    // "Sailfish.Contacts.ContactCardPage" -> the file in the QML import path.
    Q_INVOKABLE QUrl resolveImportPage(const QString &source) const;

signals:
    void pressedChanged();
    void backNavigationChanged();
    void forwardNavigationChanged();
    void navigationStyleChanged();
    void differencesChanged();
    void pressed();
    void released();
    void canceled();

protected:
    bool childMouseEventFilter(QQuickItem *item, QEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void mouseUngrabEvent() override;
    void touchEvent(QTouchEvent *event) override;
    void touchUngrabEvent() override;

private:
    bool wantsDrag(const QPointF &delta) const;
    void setDelta(const QPointF &delta);
    void finish(bool release);

    QPointF m_pressPos;
    int m_pointId = -1;
    QPointF m_delta;
    bool m_tracking = false;
    bool m_pressed = false;
    bool m_back = false;
    bool m_forward = false;
    int m_style = 0;
};

#endif // KEEL_PAGESTACKGESTURE_H
