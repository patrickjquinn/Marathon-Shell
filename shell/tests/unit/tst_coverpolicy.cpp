// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include <QtTest>

#include "core/coverpolicy.h"

using namespace keel;

class TestCoverPolicy : public QObject
{
    Q_OBJECT
private slots:
    void titleMarker_data()
    {
        QTest::addColumn<QString>("title");
        QTest::addColumn<bool>("cover");
        QTest::newRow("exact") << "keel:cover" << true;
        QTest::newRow("labelled") << "keel:cover:Weather" << true;
        QTest::newRow("empty label") << "keel:cover:" << true;
        QTest::newRow("prefix without colon") << "keel:covered" << false;
        QTest::newRow("case differs") << "Keel:Cover" << false;
        QTest::newRow("leading space") << " keel:cover" << false;
        QTest::newRow("ordinary") << "Weather" << false;
        QTest::newRow("empty") << "" << false;
    }
    void titleMarker()
    {
        QFETCH(QString, title);
        QFETCH(bool, cover);
        SurfaceInfo info;
        info.title = title;
        QCOMPARE(CoverPolicy().isCover(info), cover);
    }

    void appIdSuffix_data()
    {
        QTest::addColumn<QString>("appId");
        QTest::addColumn<bool>("cover");
        QTest::newRow("suffix") << "org.example.weather.keel-cover" << true;
        QTest::newRow("bare suffix") << ".keel-cover" << false;
        QTest::newRow("plain .cover is not enough") << "org.example.cover" << false;
        QTest::newRow("app id") << "org.example.weather" << false;
    }
    void appIdSuffix()
    {
        QFETCH(QString, appId);
        QFETCH(bool, cover);
        SurfaceInfo info;
        info.appId = appId;
        QCOMPARE(CoverPolicy().isCover(info), cover);
    }

    void childrenAreNeverCovers()
    {
        SurfaceInfo info;
        info.title = QStringLiteral("keel:cover");
        for (SurfaceKind k : { SurfaceKind::Transient, SurfaceKind::Popup, SurfaceKind::SubSurface }) {
            info.kind = k;
            QVERIFY(!CoverPolicy().isCover(info));
        }
        info.kind = SurfaceKind::Toplevel;
        QVERIFY(CoverPolicy().isCover(info));
        info.kind = SurfaceKind::Unknown;
        QVERIFY(CoverPolicy().isCover(info));
    }

    void customMarker()
    {
        CoverPolicy p(QStringLiteral("__cover__"));
        SurfaceInfo info;
        info.title = QStringLiteral("__cover__");
        QVERIFY(p.isCover(info));
        info.title = QStringLiteral("keel:cover");
        QVERIFY(!p.isCover(info));
        QCOMPARE(CoverPolicy(QString()).titleMarker(), CoverPolicy::defaultTitleMarker());
    }

    void label()
    {
        QCOMPARE(CoverPolicy().coverLabel(QStringLiteral("keel:cover:Weather")), QStringLiteral("Weather"));
        QCOMPARE(CoverPolicy().coverLabel(QStringLiteral("keel:cover")), QString());
    }
};

QTEST_GUILESS_MAIN(TestCoverPolicy)
#include "tst_coverpolicy.moc"
