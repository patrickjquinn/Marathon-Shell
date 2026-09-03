#include <QQmlEngine>
#include <QJSEngine>
#include <QtQml>
#include "testrunnerwrapper.h"

class TestRunnerHookHelper : public TestRunner {
public:
    virtual void execEngineHook(QQmlEngine* engine);
};

void TestRunnerHookHelper::execEngineHook(QQmlEngine *engine)
{
    TestRunner::execEngineHook(engine);
}


TestRunnerWrapper::TestRunnerWrapper(QObject *parent) : QObject(parent)
{

}

QStringList TestRunnerWrapper::arguments() const
{
    QStringList res;
    TestRunner* runner = TestRunner::defaultInstance();

    if (runner) {
        res = runner->arguments();
    }

    return res;
}

QVariantMap TestRunnerWrapper::config() const
{
    QVariantMap res;
    TestRunner* runner = TestRunner::defaultInstance();
    if (runner) {
        res = runner->config();
    }
    return res;
}

QString TestRunnerWrapper::prepare(const QString &dummy) const
{
    return dummy;
}

static QObject *provider(QQmlEngine *engine, QJSEngine *scriptEngine) {
    Q_UNUSED(engine);
    Q_UNUSED(scriptEngine);

    TestRunnerWrapper* object = new TestRunnerWrapper();

    TestRunner* runner = TestRunner::defaultInstance();
    if (runner) {
        TestRunnerHookHelper *helper = static_cast<TestRunnerHookHelper*>(runner);
        helper->execEngineHook(engine);
    }

    return object;
}

static void registerSingleton() {
    qmlRegisterSingletonType<TestRunnerWrapper>("Testable", 1, 0, "TestRunner", provider);
}

Q_COREAPP_STARTUP_FUNCTION(registerSingleton)

