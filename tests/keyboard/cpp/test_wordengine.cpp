#include "qml/keyboard/Data/WordEngine.h"
#include <QSignalSpy>
#include <QtTest/QtTest>

class TestWordEngine : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase();
    void cleanupTestCase();
    void testEnabledProperty();
    void testLanguageProperty();
    void testRequestPredictions();
    void testLearnWord();
    void testSpellCheck();
    void testZeroMaxResults();
    void testNegativeMaxResults();
    void testConcurrentRequests();
    void testEmptyLanguage();

  private:
    WordEngine *engine = nullptr;
};

void TestWordEngine::initTestCase() {
    engine = new WordEngine(this);
    QTest::qWait(500);
}

void TestWordEngine::cleanupTestCase() {
    delete engine;
    engine = nullptr;
}

void TestWordEngine::testEnabledProperty() {
    QVERIFY(engine->enabled());
    QSignalSpy spy(engine, &WordEngine::enabledChanged);
    engine->setEnabled(false);
    QVERIFY(!engine->enabled());
    QCOMPARE(spy.count(), 1);
    engine->setEnabled(true);
    QVERIFY(engine->enabled());
}

void TestWordEngine::testLanguageProperty() {
    QCOMPARE(engine->language(), QString("en_US"));
    QSignalSpy spy(engine, &WordEngine::languageChanged);
    engine->setLanguage("fr_FR");
    QCOMPARE(engine->language(), QString("fr_FR"));
    QCOMPARE(spy.count(), 1);
    engine->setLanguage("en_US");
}

void TestWordEngine::testRequestPredictions() {
    QSignalSpy spy(engine, &WordEngine::predictionsReady);
    engine->requestPredictions("hel", 3);
    QVERIFY(spy.wait(2000));
    QCOMPARE(spy.count(), 1);
    QList<QVariant> arguments   = spy.takeFirst();
    QString         prefix      = arguments.at(0).toString();
    QStringList     predictions = arguments.at(1).toStringList();
    QCOMPARE(prefix, QString("hel"));
    QVERIFY(predictions.size() > 0);
    QVERIFY(predictions.size() <= 3);
}

void TestWordEngine::testLearnWord() {
    QString testWord = "marathontest123";
    engine->learnWord(testWord);
    QTest::qWait(500);
    QSignalSpy spy(engine, &WordEngine::predictionsReady);
    engine->requestPredictions("marathon", 10);
    QVERIFY(spy.wait(2000));
    QList<QVariant> arguments   = spy.takeFirst();
    QStringList     predictions = arguments.at(1).toStringList();
    QVERIFY(predictions.contains(testWord));
}

void TestWordEngine::testSpellCheck() {
    QVERIFY(engine->spell("hello"));
    QVERIFY(engine->spell("world"));
}

void TestWordEngine::testZeroMaxResults() {
    QSignalSpy spy(engine, &WordEngine::predictionsReady);
    engine->requestPredictions("test", 0);
    QVERIFY(spy.wait(2000));
    QList<QVariant> args    = spy.takeFirst();
    QStringList     results = args.at(1).toStringList();
    QCOMPARE(results.size(), 0);
}

void TestWordEngine::testNegativeMaxResults() {
    QSignalSpy spy(engine, &WordEngine::predictionsReady);
    engine->requestPredictions("test", -1);
    QVERIFY(spy.wait(2000));
    QList<QVariant> args    = spy.takeFirst();
    QStringList     results = args.at(1).toStringList();
    QCOMPARE(results.size(), 0);
}

void TestWordEngine::testConcurrentRequests() {
    QSignalSpy spy(engine, &WordEngine::predictionsReady);
    engine->requestPredictions("hello", 3);
    engine->requestPredictions("world", 3);
    engine->requestPredictions("test", 3);
    QVERIFY(spy.count() >= 0);
    while (spy.count() < 3 && spy.wait(1000)) {}
    QVERIFY(spy.count() >= 1);
}

void TestWordEngine::testEmptyLanguage() {
    engine->setLanguage("");
    QCOMPARE(engine->language(), QString(""));
    engine->setLanguage("en_US");
}

QTEST_MAIN(TestWordEngine)
#include "test_wordengine.moc"
