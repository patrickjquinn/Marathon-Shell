// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// InverseMouseArea (Sailfish.Silica.private): reports presses and clicks
// outside its own bounds anywhere in its window. API inferred from Silica's
// BSD QML (ContextMenu, DockedPanel, PulleyMenuBase, TextBase):
// `pressedOutside()`, `clickedOutside()`, `stealPress`, `cancelTouch()`.
// Clean-room behaviour: while enabled and visible, the item watches its
// window's pointer events. A press outside emits pressedOutside(); with
// stealPress the press is not delivered to the item under it (nor the rest
// of that touch). A release outside, near where the press was, emits
// clickedOutside(). cancelTouch() takes the current press away from the item
// that received it.
#ifndef KEEL_INVERSEMOUSEAREA_H
#define KEEL_INVERSEMOUSEAREA_H

#include <QPointF>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

class KeelInverseMouseArea : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(InverseMouseArea)
    Q_PROPERTY(bool stealPress READ stealPress WRITE setStealPress NOTIFY stealPressChanged)
    Q_PROPERTY(bool pressed READ pressed NOTIFY pressedChanged)

public:
    explicit KeelInverseMouseArea(QQuickItem *parent = nullptr);
    ~KeelInverseMouseArea() override;

    bool stealPress() const { return m_stealPress; }
    void setStealPress(bool steal);
    bool pressed() const { return m_pressed; }

    Q_INVOKABLE void cancelTouch();

signals:
    void stealPressChanged();
    void pressedChanged();
    void pressedOutside();
    void clickedOutside();

protected:
    void itemChange(ItemChange change, const ItemChangeData &data) override;
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void updateFilter();
    bool outside(const QPointF &scenePos) const;
    bool handlePress(const QPointF &scenePos);
    bool handleRelease(const QPointF &scenePos);
    void setPressed(bool pressed);

    QPointer<QQuickWindow> m_window;
    QPointF m_pressPos;
    bool m_stealPress = false;
    bool m_pressed = false;
    bool m_stealing = false;
    bool m_cancel = false;
};

#endif // KEEL_INVERSEMOUSEAREA_H
