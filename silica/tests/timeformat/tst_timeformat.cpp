// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Format's times follow the phone's 24-hour clock setting (dconf
// /sailfish/i18n/lc_timeformat24h, '24' or '12'), and the locale when it is
// unset. dconf is a fake program (fake-dconf.sh through KEEL_DCONF) that
// prints $KEEL_TEST_TIMEFORMAT24H for that key.

#include <QtTest>

#include "format.h"

using keel::clock::Hours;

class tst_TimeFormat : public QObject
{
    Q_OBJECT

private:
    static void setSetting(const char *value)
    {
        if (value)
            qputenv("KEEL_TEST_TIMEFORMAT24H", value);
        else
            qunsetenv("KEEL_TEST_TIMEFORMAT24H");
    }

    // 8 October 2026, 18:05 local time.
    static QDateTime evening() { return QDateTime(QDate(2026, 10, 8), QTime(18, 5)); }

private slots:
    void initTestCase()
    {
        qputenv("KEEL_DCONF", QByteArray(KEEL_FAKE_DCONF));
    }

    void cleanup()
    {
        setSetting(nullptr);
        QLocale::setDefault(QLocale::c());
    }

    void parse_data()
    {
        QTest::addColumn<QString>("text");
        QTest::addColumn<int>("hours");
        QTest::newRow("string 24") << "'24'" << static_cast<int>(Hours::TwentyFour);
        QTest::newRow("string 12") << "'12'" << static_cast<int>(Hours::Twelve);
        QTest::newRow("bare 24") << "24" << static_cast<int>(Hours::TwentyFour);
        QTest::newRow("unset") << "" << static_cast<int>(Hours::Locale);
        QTest::newRow("other") << "'auto'" << static_cast<int>(Hours::Locale);
    }

    void parse()
    {
        QFETCH(QString, text);
        QFETCH(int, hours);
        QCOMPARE(int(keel::clock::parse(text)), hours);
    }

    void adjust_data()
    {
        QTest::addColumn<QString>("format");
        QTest::addColumn<int>("hours");
        QTest::addColumn<QString>("expected");
        QTest::newRow("US to 24") << "h:mm AP" << static_cast<int>(Hours::TwentyFour) << "HH:mm";
        QTest::newRow("US date-time to 24") << "M/d/yy h:mm AP" << static_cast<int>(Hours::TwentyFour) << "M/d/yy HH:mm";
        QTest::newRow("marker first to 24") << "AP h:mm" << static_cast<int>(Hours::TwentyFour) << "HH:mm";
        QTest::newRow("German to 12") << "HH:mm" << static_cast<int>(Hours::Twelve) << "h:mm AP";
        QTest::newRow("Finnish to 12") << "H.mm" << static_cast<int>(Hours::Twelve) << "h.mm AP";
        QTest::newRow("Finnish stays 24") << "H.mm" << static_cast<int>(Hours::TwentyFour) << "H.mm";
        QTest::newRow("US stays 12") << "h:mm AP" << static_cast<int>(Hours::Twelve) << "h:mm AP";
        QTest::newRow("quoted literal") << "'klo' H.mm" << static_cast<int>(Hours::Twelve) << "'klo' h.mm AP";
        QTest::newRow("locale") << "h:mm AP" << static_cast<int>(Hours::Locale) << "h:mm AP";
        QTest::newRow("date only") << "dd.MM.yy" << static_cast<int>(Hours::Twelve) << "dd.MM.yy";
    }

    void adjust()
    {
        QFETCH(QString, format);
        QFETCH(int, hours);
        QFETCH(QString, expected);
        QCOMPARE(keel::clock::adjust(format, Hours(hours)), expected);
    }

    void setting()
    {
        setSetting("'24'");
        QCOMPARE(keel::clock::setting(), Hours::TwentyFour);
        setSetting("'12'");
        QCOMPARE(keel::clock::setting(), Hours::Twelve);
        setSetting(nullptr);
        QCOMPARE(keel::clock::setting(), Hours::Locale);
    }

    void timeValue_data()
    {
        QTest::addColumn<QString>("locale");
        QTest::addColumn<QByteArray>("setting");
        QTest::addColumn<QString>("expected");
        // The phone's setting wins over the locale's habit, both ways.
        QTest::newRow("en_US, 24h set") << "en_US" << QByteArray("'24'") << "18:05";
        QTest::newRow("en_US, 12h set") << "en_US" << QByteArray("'12'") << "6:05 PM";
        QTest::newRow("de_DE, 12h set") << "de_DE" << QByteArray("'12'") << "6:05 PM";
        QTest::newRow("de_DE, 24h set") << "de_DE" << QByteArray("'24'") << "18:05";
        QTest::newRow("fi_FI, 24h set") << "fi_FI" << QByteArray("'24'") << "18.05";
        // Unset: the locale's own clock.
        QTest::newRow("de_DE, unset") << "de_DE" << QByteArray() << "18:05";
    }

    void timeValue()
    {
        QFETCH(QString, locale);
        QFETCH(QByteArray, setting);
        QFETCH(QString, expected);
        setSetting(setting.isEmpty() ? nullptr : setting.constData());
        QLocale::setDefault(QLocale(locale));
        KeelFormatter f;
        QString text = f.formatDate(evening(), KeelFormatter::TimeValue);
        // CLDR's 12-hour separator before AM/PM varies (space or narrow
        // no-break space) between ICU releases.
        text.replace(QChar(0x202f), QLatin1Char(' '));
        expected.replace(QChar(0x202f), QLatin1Char(' '));
        QCOMPARE(text, expected);
        // The time of a timestamp from today follows it too.
        f._setReferenceTime(evening().addSecs(60));
        QString relative = f.formatDate(evening(), KeelFormatter::TimepointRelative);
        relative.replace(QChar(0x202f), QLatin1Char(' '));
        QCOMPARE(relative, expected);
    }

    void twentyFourHours()
    {
        setSetting(nullptr);
        QVERIFY(keel::clock::twentyFourHours(QLocale(QStringLiteral("de_DE"))));
        QVERIFY(!keel::clock::twentyFourHours(QLocale(QStringLiteral("en_US"))));
        setSetting("'24'");
        QVERIFY(keel::clock::twentyFourHours(QLocale(QStringLiteral("en_US"))));
        setSetting("'12'");
        QVERIFY(!keel::clock::twentyFourHours(QLocale(QStringLiteral("de_DE"))));
    }
};

QTEST_GUILESS_MAIN(tst_TimeFormat)
#include "tst_timeformat.moc"
