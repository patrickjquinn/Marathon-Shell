#include <QQuickWindow>
#include <QEventLoop>
#include <QTimer>
#include <QQuickItem>
#include <QTime>
#include <QTest>
#include <QSignalSpy>
#include <QRegularExpression>
#include "automator.h"
#include "priv/objectutils.h"
#include "testablefunctions.h"

using namespace Testable;

static bool hasMethod(QObject* object, QString method) {
    const QMetaObject* meta = object->metaObject();

    int index = -1;

    for (int i = 0 ; i < meta->methodCount(); i++) {
        if (method == meta->method(i).name()) {
            index = i;
            break;
        }
    }

    return index >= 0;
}

static bool hasMethods(QObject* object, QStringList filters) {

    const QMetaObject* meta = object->metaObject();

    bool res = false;

    for (int i = 0 ; i < meta->methodCount(); i++) {
        if (filters.indexOf(meta->method(i).name()) >= 0) {
            res = true;
            break;
        }
    }

    return res;
}

static void invokeMethod(QObject*object, QString method, QJSValue jsObject) {
    QJSValue func = jsObject.property(method);
    QJSValue result = func.call();

    if (result.isError()) {
        QStringList stack = result.property("stack").toString().split("\n");

        QStringList pair = stack[0].split("@");
        QString source = pair[1];

        if (source.indexOf(QRegularExpression("qrc:/*Testable/TestableCase.qml")) == 0) {
            pair = stack[1].split("@");
            source = pair[1];
        }

        QString message = result.property("message").toString();

        qWarning().noquote() << source + ":" << "Error:" << message;
        object->setProperty("hasError", true);
    }
}

static void invokeMethodIfPresent(QObject* object, QString method, QJSValue jsObject) {
    if (hasMethod(object, method)) {
        invokeMethod(object,method, jsObject);
    }
}

static void invokeTestableCase(QQmlEngine* engine, QObject* object, QStringList filters) {
    const QMetaObject* meta = object->metaObject();

    QJSValue jsObject = engine->newQObject(object);

    invokeMethodIfPresent(object,"initTestCase", jsObject);

    for (int j = 0 ; j < meta->methodCount();j++) {
        const QMetaMethod method = meta->method(j);
        QString methodName = method.name();

        if (methodName.indexOf("test_") == 0 &&
            (filters.size() == 0 || filters.indexOf(methodName) >= 0)) {
            invokeMethodIfPresent(object, "init", jsObject);
            invokeMethod(object,methodName,jsObject);
            invokeMethodIfPresent(object, "cleanup", jsObject);
        }
    }

    invokeMethodIfPresent(object,"cleanupTestCase", jsObject);
}

Automator::Automator(QQmlApplicationEngine* engine) : QObject()
{
    setEngine(engine);
    m_anyError = false;
}


QQmlApplicationEngine *Automator::engine() const
{
    return m_engine;
}

void Automator::setEngine(QQmlApplicationEngine *engine)
{
    m_engine = engine;
    connect(engine,SIGNAL(warnings(QList<QQmlError>)),
            this,SLOT(onWarnings(QList<QQmlError>)));
}

void Automator::wait(int timeout) {

    QEventLoop loop;
    QTimer timer;
    QObject::connect(&timer,SIGNAL(timeout()),
            &loop,SLOT(quit()));
    timer.start(timeout);
    loop.exec();

}

QObject *Automator::findObject(QString objectName)
{
    QObjectList list = findObjects(objectName);
    QObject* res = 0;

    if (list.size() > 0) {
        res = list.first();
    }

    return res;
}

QObjectList Automator::findObjects(QString objectName)
{
    QObjectList result;

    foreach (QObject* object, m_engine->rootObjects()) {
        QObjectList subResult = findObjects(object, objectName);

        if (subResult.size() > 0) {
            result << subResult;
        }
    }

    return ObjectUtils::uniq(result);
}

bool Automator::waitExists(QString objectName, int timeout)
{
    QElapsedTimer time;
    time.start();

    while (true) {
        QObject* object = findObject(objectName);
        if (object) {
            break;
        }
        wait(100);

        if (time.elapsed() > timeout) {
            qWarning() << "waitExists() : Time out";
            return false;
        }
    }

    return true;

}

bool Automator::waitUntil(QObject *object, QString property, QVariant value, int timeout)
{
    QVariant objectValue = object->property(property.toLocal8Bit().constData());
    QElapsedTimer time;
    time.start();

    while (objectValue != value) {
        wait(100);
        objectValue = object->property(property.toLocal8Bit().constData());

        if (time.elapsed() > timeout) {
            qWarning() << "waitUntil() : Time out";
            return false;
        }
    }
    return true;
}

bool Automator::waitUntilSignal(QObject *object, const char *signal, int timeout)
{
    QTimer timer;
    QSignalSpy spy(&timer,SIGNAL(timeout()));

    QEventLoop loop;

    if (timeout > 0) {
        // Avoid using lambda function with QTimer::timeout to keep travis happy
        timer.setInterval(timeout);
        timer.setSingleShot(true);
        connect(&timer,SIGNAL(timeout()), &loop,SLOT(quit()));
        timer.start();
    }
    connect(object,signal,&loop,SLOT(quit()));

    loop.exec();
    timer.stop();

    return spy.count() == 0;
}

bool Automator::waitUntil(QString objectName, QString property, QVariant value, int timeout)
{
    QElapsedTimer time;
    time.start();

    QObject* object = findObject(objectName);
    if (!object) {
        qWarning() << "Object not found" << objectName;
        return false;
    }

    return waitUntil(object, property, value, timeout);
}

bool Automator::click(QQuickItem *item, int delay,  QPointF pt)
{
    QQuickWindow* win = window();
    if (!win) {
        qWarning() << "click: No window object";
        return false;
    }

    QPointF hit;
    if (pt.isNull()) {
        int w = item->width();
        int h = item->height();
        int cx =  w /2;
        int cy =  h / 2;
        hit = item->mapToScene(QPointF(cx,cy));
    } else {
        hit = item->mapToScene(pt);
    }

    QTest::mouseClick(win, Qt::LeftButton,
                      Qt::NoModifier,
                      hit.toPoint(),
                      delay);
    return true;
}

bool Automator::click(QQuickItem *item, QString childObjectName)
{
    QObjectList list = findObjects(item, childObjectName);
    QQuickItem* child = 0;

    if (list.size() == 0) {
        return false;
    }

    child = qobject_cast<QQuickItem*>(list.first());
    if (!child) {
        return false;
    }

    return click(child);
}

bool Automator::click(QString objectName, int delay, QPointF point)
{
    QQuickItem* item = qobject_cast<QQuickItem*>(findObject(objectName));

    if (!item) {
        qWarning() << "Object not found" << objectName;
        return false;
    }

    return click(item, delay, point);
}

QObjectList Automator::findObjects(QObject *object, QString objectName)
{
    QObjectList result;

    if (!object) {
        return result;
    }

    if (object->objectName() == objectName) {
        result << object;
    }

    if (inherited(object,"QQuickRepeater")) {
        int count = object->property("count").toInt();

        for (int i = 0 ;  i < count ;i++) {
            QQuickItem* item;
            QMetaObject::invokeMethod(object,"itemAt",Qt::DirectConnection,
                                      Q_RETURN_ARG(QQuickItem*,item),
                                      Q_ARG(int,i));
            QObjectList subResult = findObjects(item, objectName);
            if (subResult.size() > 0) {
                result.append(subResult);
            }
        }

    } else if (inherited(object, "QQuickFlickable") || inherited(object, "QQuickWindow")) {

        QQuickItem* contentItem = object->property("contentItem").value<QQuickItem*>();

        if (contentItem) {

            QList<QQuickItem *>items = contentItem->childItems() ;

            for (int i = 0 ;  i < items.size() ; i++) {
                QObjectList subResult = findObjects(items.at(i),objectName);
                if (subResult.size() > 0) {
                    result.append(subResult);
                }
            }

            QObjectList subResult = findObjects(contentItem, objectName);
            if (subResult.size() > 0) {
                result.append(subResult);
            }
        }
    }

    QObjectList children = object->children();

    for (int i = 0 ; i < children.size();i++) {
        QObjectList subResult = findObjects(children.at(i), objectName);

        if (subResult.size() > 0) {
            result.append(subResult);
        }
    }

    return ObjectUtils::uniq(result);
}

QQuickWindow *Automator::window()
{
    QObject *firstObject = m_engine->rootObjects().first();
    QQuickWindow *window = qobject_cast<QQuickWindow*>(firstObject);

    return window;
}

bool Automator::anyError() const
{
    return m_anyError;
}

void Automator::setAnyError(bool anyError)
{
    m_anyError = anyError;
}

QObject* Automator::obtainSingletonObject(QString package, int versionMajor, int versionMinor, QString typeName)
{
    /// Modified from QFAppDispatcher::singletonObject() in QuickFlux project
    QString pattern  = "import QtQuick 2.0\nimport %1 %2.%3;QtObject { property var object : %4 }";

    QString qml = pattern.arg(package).arg(versionMajor).arg(versionMinor).arg(typeName);

    QObject* holder = 0;

    QQmlComponent comp (m_engine.data());
    comp.setData(qml.toUtf8(),QUrl());
    holder = comp.create();

    if (!holder) {
        qWarning() << QString("Testable: Failed to gain singleton object: %1").arg(typeName);
        qWarning() << QString("Error: ") << comp.errorString();
        return 0;
    }

    QObject* object = holder->property("object").value<QObject*>();
    holder->deleteLater();

    if (!object) {
        qWarning() << QString("Testable: Failed to gain singleton object: %1").arg(typeName);
        qWarning() << QString("Error: Unknown");
    }

    return object;
}

void Automator::onWarnings(QList<QQmlError> warnings)
{
    for (int i = 0 ; i < warnings.size();i++){
        if (warnings.at(i).toString().indexOf("Error") != -1) {
            setAnyError(true);
        }
    }
}
