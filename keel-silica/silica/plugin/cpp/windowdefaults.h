// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// What Silica's BSD QML reads from `__silica_applicationwindow_instance` when
// a component is used outside an ApplicationWindow (a plain QQuickView, a
// test). Keel's own: installed as that context property on every engine;
// an ApplicationWindow's property of the same name shadows it for
// everything created inside the window. Defaults match Keel's
// ApplicationWindow; the window items are one off-screen item as large as
// the screen in portrait (QML that sizes itself from them keeps working),
// _contentScale and pageStack are null.
#ifndef KEEL_WINDOWDEFAULTS_H
#define KEEL_WINDOWDEFAULTS_H

#include <QColor>
#include <QGuiApplication>
#include <QObject>
#include <QQuickItem>
#include <QScreen>

class KeelWindowDefaults : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool _dimScreen MEMBER m_dimScreen NOTIFY dimScreenChanged)
    Q_PROPERTY(bool _dimmingActive READ dimScreen NOTIFY dimScreenChanged)
    Q_PROPERTY(int _defaultLabelFormat READ defaultLabelFormat CONSTANT)
    Q_PROPERTY(int _defaultPageOrientations READ portrait CONSTANT)
    Q_PROPERTY(int allowedOrientations READ allOrientations CONSTANT)
    Q_PROPERTY(int deviceOrientation READ portrait CONSTANT)
    Q_PROPERTY(int orientation READ portrait CONSTANT)
    Q_PROPERTY(int defaultPageCutoutMode READ avoidLandscapeCutout CONSTANT)
    Q_PROPERTY(bool _rotating READ no CONSTANT)
    Q_PROPERTY(bool _backgroundVisible READ yes CONSTANT)
    Q_PROPERTY(QColor _backgroundColor READ transparent CONSTANT)
    Q_PROPERTY(QQuickItem *contentItem READ screenItem CONSTANT)
    Q_PROPERTY(QQuickItem *_rotatingItem READ screenItem CONSTANT)
    Q_PROPERTY(QQuickItem *_touchBlockerItem READ screenItem CONSTANT)
    Q_PROPERTY(QQuickItem *indicatorParentItem READ screenItem CONSTANT)
    Q_PROPERTY(QObject *_contentScale READ noObject CONSTANT)
    Q_PROPERTY(QQuickItem *pageStack READ noItem CONSTANT)

public:
    explicit KeelWindowDefaults(QObject *parent = nullptr)
        : QObject(parent)
        , m_screenItem(new QQuickItem)
    {
        m_screenItem->setParent(this);
        if (QScreen *screen = QGuiApplication::primaryScreen()) {
            const QSize s = screen->size();
            m_screenItem->setSize(QSizeF(qMin(s.width(), s.height()), qMax(s.width(), s.height())));
        }
    }
    QQuickItem *screenItem() const { return m_screenItem; }

    bool dimScreen() const { return m_dimScreen; }
    // Text.AutoText, as Silica's ApplicationWindow.
    int defaultLabelFormat() const { return 2; }
    int portrait() const { return 1; }
    int allOrientations() const { return 15; }
    // CutoutMode.AvoidLandscapeCutout
    int avoidLandscapeCutout() const { return 1; }
    bool no() const { return false; }
    bool yes() const { return true; }
    QColor transparent() const { return Qt::transparent; }
    QQuickItem *noItem() const { return nullptr; }
    QObject *noObject() const { return nullptr; }

    Q_INVOKABLE int _selectOrientation(int allowed) const { return _selectOrientation(allowed, portrait()); }
    Q_INVOKABLE int _selectOrientation(int allowed, int device) const
    {
        if (device & allowed)
            return device;
        for (int o : { 1, 2, 8, 4 }) {
            if (o & allowed)
                return o;
        }
        return 1;
    }

signals:
    void dimScreenChanged();

private:
    bool m_dimScreen = false;
    QQuickItem *m_screenItem;
};

#endif // KEEL_WINDOWDEFAULTS_H
