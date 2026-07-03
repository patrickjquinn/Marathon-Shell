#include <QEventLoop>
#include <QTimer>
#include <QtQml>
#include <QTest>
#include "testableutils.h"
#include "objectutils.h"

using namespace Testable;

TestableUtils::TestableUtils(QObject *parent) : QObject(parent)
{

}

void TestableUtils::wait(int timeout)
{
    QEventLoop loop;
    QTimer timer;
    QObject::connect(&timer,SIGNAL(timeout()),
            &loop,SLOT(quit()));
    timer.start(timeout);
    loop.exec();
}

QObject *TestableUtils::findChild(QObject *parent, const QString &objectName)
{
    QObjectList list = ObjectUtils::allChildren(parent);

    QObject *res = 0;
    foreach (QObject* object, list) {
        if (object->objectName() == objectName) {
            res = object;
            break;
        }
    }

    return res;
}

static QObject *provider(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(engine);
    Q_UNUSED(scriptEngine);

    TestableUtils* object = new TestableUtils();

    return object;
}

static void registerTestableUtils() {
    qmlRegisterSingletonType<TestableUtils>("Testable", 1, 0, "TestableUtils", provider);
}

Q_COREAPP_STARTUP_FUNCTION(registerTestableUtils)
