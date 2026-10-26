#include <QCoreApplication>
#include <QLocale>
#include <QSignalSpy>
#include <QTest>

#include "translations.h"

class TestTranslations : public QObject {
    Q_OBJECT

  private slots:
    void installsTheCatalog() {
        Translations translations({QStringLiteral("test")}, nullptr);
        QSignalSpy   installed(&translations, &Translations::installed);
        QVERIFY(translations.install(QStringLiteral("de")));
        QCOMPARE(QCoreApplication::translate("Ctx", "Hello"), QStringLiteral("Hallo"));
        QCOMPARE(translations.code(), QStringLiteral("de"));
        QCOMPARE(installed.size(), 1);
        QCOMPARE(installed.first().first().toString(), QStringLiteral("de"));
    }

    void unknownLanguageFallsBack() {
        QTest::failOnWarning();
        Translations translations({QStringLiteral("test")}, nullptr);
        QVERIFY(!translations.install(QStringLiteral("xx")));
        QCOMPARE(QCoreApplication::translate("Ctx", "Hello"), QStringLiteral("Hello"));
    }

    void switchingReplacesTheOld() {
        Translations translations({QStringLiteral("test")}, nullptr);
        translations.install(QStringLiteral("de"));
        translations.install(QStringLiteral("en"));
        QCOMPARE(QCoreApplication::translate("Ctx", "Hello"), QStringLiteral("Hello"));
    }

    void setsLocale() {
        Translations translations({QStringLiteral("test")}, nullptr);
        translations.install(QStringLiteral("de"));
        QCOMPARE(QLocale().name(), QStringLiteral("de_DE"));
    }

    void setsTheEnvironment() {
        Translations translations({QStringLiteral("test")}, nullptr);
        translations.install(QStringLiteral("de"));
        QCOMPARE(qgetenv("LANGUAGE"), QByteArray("de"));
        QCOMPARE(qgetenv("LANG"), QByteArray("de_DE.UTF-8"));
        translations.install(QStringLiteral("en_XA"));
        QCOMPARE(qgetenv("LANG"), QByteArray("en_US.UTF-8"));
        QCOMPARE(qgetenv("LANGUAGE"), QByteArray("en_XA"));
    }

    void emptySettingRestoresTheImageLocale() {
        qputenv("LANG", "en_IE.UTF-8");
        qunsetenv("LANGUAGE");
        Translations translations({QStringLiteral("test")}, nullptr);
        translations.install(QStringLiteral("de"));
        translations.install(QString());
        QCOMPARE(qgetenv("LANG"), QByteArray("en_IE.UTF-8"));
        QVERIFY(!qEnvironmentVariableIsSet("LANGUAGE"));
        QCOMPARE(QLocale().name(), QStringLiteral("en_IE"));
        QCOMPARE(QCoreApplication::translate("Ctx", "Hello"), QStringLiteral("Hello"));
    }
};

QTEST_GUILESS_MAIN(TestTranslations)
#include "test_translations.moc"
