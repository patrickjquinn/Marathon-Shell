// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see misc.h.

#include "misc.h"

#include <QDate>
#include <QFile>
#include <QGuiApplication>
#include <QMetaMethod>
#include <QPointer>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QTimer>

KeelPrivateUtil::KeelPrivateUtil(QObject *parent)
    : QObject(parent)
{
}

void KeelPrivateUtil::asyncInvoke(const QJSValue &function)
{
    if (!function.isCallable())
        return;
    QTimer::singleShot(0, this, [f = function]() mutable { f.call(); });
}

bool KeelPrivateUtil::instanceOf(QObject *object, const QString &className) const
{
    return object && object->inherits(className.toLatin1().constData());
}

QVariantList KeelPrivateUtil::weekNumberList(int year, int month, int day, int count) const
{
    Q_UNUSED(day)
    QVariantList out;
    QDate d(year, month, 1);
    if (!d.isValid())
        return out;
    for (int i = 0; i < count; ++i)
        out << d.addDays(static_cast<qint64>(7) * i).weekNumber();
    return out;
}

// Headless runs (the offscreen and minimal platforms: smoke tests, CI) have
// nothing to animate for, and app test harnesses written against Keel's
// earlier immediate page stack poll for the new page without waiting for a
// transition. There, an animated push, pop or replace completes at once.
// KEEL_PAGE_TRANSITIONS=1 keeps the animations, KEEL_PAGE_TRANSITIONS=0 drops
// them on any platform; Keel's own tests that check transitions set the
// property to false.
static bool defaultImmediatePageTransitions()
{
    const QByteArray env = qgetenv("KEEL_PAGE_TRANSITIONS");
    if (env == "1")
        return false;
    if (env == "0")
        return true;
    const QString platform = QGuiApplication::platformName();
    return platform == QLatin1String("offscreen") || platform == QLatin1String("minimal");
}

KeelPrivateConfig::KeelPrivateConfig(QObject *parent)
    : QObject(parent)
    , m_immediatePageTransitions(defaultImmediatePageTransitions())
{
}

void KeelPrivateConfig::setImmediatePageTransitions(bool immediate)
{
    if (m_immediatePageTransitions == immediate)
        return;
    m_immediatePageTransitions = immediate;
    emit immediatePageTransitionsChanged();
}

bool KeelPrivateConfig::desktop() const
{
    return !QFile::exists(QStringLiteral("/etc/sailfish-release"));
}

bool KeelPrivateConfig::wayland() const
{
    return QGuiApplication::platformName().startsWith(QLatin1String("wayland"));
}

bool KeelPrivateConfig::layoutGrid() const
{
    return qEnvironmentVariableIsSet("KEEL_LAYOUT_GRID");
}

// Qt's ListView and GridView create their header (footer) item with
// QQmlComponent::beginCreate() and completeCreate(), and store it only after
// completeCreate() returns (QQuickListViewPrivate::updateHeader(), unchanged
// from Qt 6.4 to dev). A positionViewAt*() call from the header's own
// handlers during that completion (harbour-mashka: `onHeightChanged:
// positionViewAtBeginning()` in a ListView header) lays the view out again,
// finds no header, and creates one again from the same component:
// beginCreate() refuses, but createComponentItem() still calls completeCreate()
// and so completes the outer creation re-entrantly. The component keeps a
// half-torn-down QQmlObjectCreator, and the process crashes when the view is
// destroyed (QUntypedPropertyBinding::~QUntypedPropertyBinding from
// ~QQmlComponent). Qt 5 tolerated the same call. SilicaListView and
// SilicaGridView route positionViewAt*() through here: while the header (or
// footer) component is set but its item does not exist yet, the call runs
// from the event loop, once the item is in place; otherwise at once. The C++
// method is invoked by its index in Qt's own meta-object, so the QML
// functions that shadow it are not re-entered.
void KeelPrivateUtil::_keelPositionView(QObject *view, const QString &method, int index, int mode)
{
    if (!view)
        return;
    const QMetaObject *mo = view->metaObject();
    while (mo && qstrcmp(mo->className(), "QQuickItemView") != 0)
        mo = mo->superClass();
    if (!mo)
        return;
    const bool atIndex = method == QLatin1String("positionViewAtIndex");
    const QByteArray signature = method.toLatin1() + (atIndex ? "(int,int)" : "()");
    const QMetaMethod m = mo->method(mo->indexOfMethod(signature.constData()));
    if (!m.isValid())
        return;
    auto call = [view = QPointer<QObject>(view), m, atIndex, index, mode]() {
        if (!view)
            return;
        if (atIndex)
            m.invoke(view, Qt::DirectConnection, Q_ARG(int, index), Q_ARG(int, mode));
        else
            m.invoke(view, Qt::DirectConnection);
    };
    const auto pending = [view](const char *component, const char *item) {
        return view->property(component).value<QObject *>() && !view->property(item).value<QObject *>();
    };
    if (pending("header", "headerItem") || pending("footer", "footerItem"))
        QTimer::singleShot(0, this, call);
    else
        call();
}

QObject *KeelPrivateUtil::_keelFindFlickable(QObject *item) const
{
    auto *i = qobject_cast<QQuickItem *>(item);
    for (QQuickItem *p = i ? i->parentItem() : nullptr; p; p = p->parentItem()) {
        if (p->property("maximumFlickVelocity").toReal() > 0
            && p->metaObject()->indexOfProperty("__silica_hidden_flickable") < 0)
            return p;
    }
    return nullptr;
}

QObject *KeelPrivateUtil::_keelOptionalObject(const QString &key, const QString &imports,
                                              const QString &body, QObject *parent)
{
    QQmlEngine *engine = qmlEngine(this);
    if (!engine)
        return nullptr;
    auto it = m_optional.constFind(key);
    if (it == m_optional.constEnd()) {
        auto *component = new QQmlComponent(engine, this);
        component->setData((imports + QLatin1Char('\n') + body).toUtf8(),
                           QUrl(QStringLiteral("keel-optional:///") + key));
        if (!component->isReady()) {
            delete component;
            component = nullptr;
        }
        it = m_optional.insert(key, component);
    }
    QQmlComponent *component = it.value();
    if (!component)
        return nullptr;
    QQmlContext *context = parent ? QQmlEngine::contextForObject(parent) : nullptr;
    QObject *object = component->beginCreate(context ? context : engine->rootContext());
    if (!object)
        return nullptr;
    object->setParent(parent);
    QQmlEngine::setObjectOwnership(object, QQmlEngine::CppOwnership);
    component->completeCreate();
    return object;
}
