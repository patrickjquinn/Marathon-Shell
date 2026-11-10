// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Small native types of Sailfish.Silica.private whose names Silica's BSD QML
// uses. Clean-room implementations.
//
//   Util (singleton): asyncInvoke(function) calls it from the event loop;
//     instanceOf(object, className) tests the C++ class (QObject::inherits);
//     weekNumberList(year, month, day, count): ISO week numbers of `count`
//     consecutive weeks, starting with the week that contains the first day
//     of `month` (1-12) of `year` (from private/DatePicker.js);
//     _keelFindFlickable(item) (Keel's own) as private/Util.js's
//     findFlickable(), evaluated without binding dependencies;
//     _keelPositionView(view, method, index, mode) (Keel's own) calls
//     QQuickItemView's positionViewAt*() on a SilicaListView/SilicaGridView,
//     deferred to the event loop while the view's header or footer is being
//     created (see misc.cpp);
//     _keelOptionalObject(key, imports, body, parent) (Keel's own) an object
//     of a type from a module that may be missing, compiled once per engine.
//   Config (singleton): desktop (true unless running on Sailfish OS),
//     wayland (the Qt platform is Wayland), layoutGrid (KEEL_LAYOUT_GRID set),
//     demoMode (always Config.None) and the DemoMode enum;
//     _keelImmediatePageTransitions (Keel's own, see misc.cpp).
//   RemorseCache (attached): `item`, the remorse item cached on an item
//     (Remorse.qml).
//   TimePickerMode, QuickScrollDirection: enum holders (values are Keel's).
#ifndef KEEL_MISC_H
#define KEEL_MISC_H

#include <QHash>
#include <QJSValue>
#include <QObject>
#include <QPointer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

class QQmlComponent;
class QQmlEngine;
class QJSEngine;

class KeelPrivateUtil : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Util)
    QML_SINGLETON

public:
    explicit KeelPrivateUtil(QObject *parent = nullptr);

    Q_INVOKABLE void asyncInvoke(const QJSValue &function);
    Q_INVOKABLE bool instanceOf(QObject *object, const QString &className) const;
    Q_INVOKABLE QVariantList weekNumberList(int year, int month, int day, int count) const;
    // Keel's: private/Util.js findFlickable() without binding dependencies
    // on the parent chain (for initial values of `flickable` properties).
    Q_INVOKABLE QObject *_keelFindFlickable(QObject *item) const;
    // Keel's: positionViewAtBeginning()/End()/Index(index, mode) of the C++
    // view, safe to call from the view's own header or footer.
    Q_INVOKABLE void _keelPositionView(QObject *view, const QString &method, int index = 0,
                                       int mode = 0);
    // Keel's: a new object of `body` (one QML object declaration) with
    // `imports` in scope, parented to `parent`, or null when its module is
    // missing. Silica made these with Qt.createQmlObject() in every component
    // instance, which compiles the source each time (about 1.5 ms on the Jolla
    // Phone, twice per pull-down menu) and for a missing module fails again
    // each time (QtFeedback, in every TextField). Here each `key` is compiled
    // once; a failure is remembered.
    Q_INVOKABLE QObject *_keelOptionalObject(const QString &key, const QString &imports,
                                             const QString &body, QObject *parent);

private:
    QHash<QString, QQmlComponent *> m_optional;
};

class KeelPrivateConfig : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Config)
    QML_SINGLETON
    Q_PROPERTY(bool desktop READ desktop CONSTANT)
    Q_PROPERTY(bool wayland READ wayland CONSTANT)
    Q_PROPERTY(bool layoutGrid READ layoutGrid CONSTANT)
    Q_PROPERTY(int demoMode READ demoMode CONSTANT)
    // Keel's: page stack transitions complete at once (see misc.cpp).
    Q_PROPERTY(bool _keelImmediatePageTransitions READ immediatePageTransitions
               WRITE setImmediatePageTransitions NOTIFY immediatePageTransitionsChanged)

public:
    enum DemoMode { None, Demo };
    Q_ENUM(DemoMode)

    explicit KeelPrivateConfig(QObject *parent = nullptr);

    bool desktop() const;
    bool wayland() const;
    bool layoutGrid() const;
    int demoMode() const { return None; }
    bool immediatePageTransitions() const { return m_immediatePageTransitions; }
    void setImmediatePageTransitions(bool immediate);

signals:
    void immediatePageTransitionsChanged();

private:
    bool m_immediatePageTransitions;
};

class KeelRemorseCacheAttached : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *item READ item WRITE setItem NOTIFY itemChanged)

public:
    explicit KeelRemorseCacheAttached(QObject *parent)
        : QObject(parent)
    {
    }
    QObject *item() const { return m_item; }
    void setItem(QObject *item)
    {
        if (item == m_item)
            return;
        m_item = item;
        emit itemChanged();
    }

signals:
    void itemChanged();

private:
    QPointer<QObject> m_item;
};

class KeelRemorseCache : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(RemorseCache)
    QML_UNCREATABLE("RemorseCache is an attached property")
    QML_ATTACHED(KeelRemorseCacheAttached)

public:
    static KeelRemorseCacheAttached *qmlAttachedProperties(QObject *object)
    {
        return new KeelRemorseCacheAttached(object);
    }
};

class KeelTimePickerMode : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TimePickerMode)
    QML_UNCREATABLE("TimePickerMode is an enum holder")

public:
    enum Mode { HoursAndMinutes, Hours, Minutes };
    Q_ENUM(Mode)
};

class KeelQuickScrollDirection : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(QuickScrollDirection)
    QML_UNCREATABLE("QuickScrollDirection is an enum holder")

public:
    enum Direction { Up = 1, Down = 2, UpAndDown = 3 };
    Q_ENUM(Direction)
};

#endif // KEEL_MISC_H
