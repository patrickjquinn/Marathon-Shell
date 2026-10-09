// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include <QGuiApplication>
#include <QScreen>
#include <QtTest>

#include "core/orientation.h"
#include "core/shellstate.h"

using namespace keel;

class TestOrientation : public QObject
{
    Q_OBJECT
private slots:
    void matchesQScreenAngleBetween()
    {
        QScreen *screen = QGuiApplication::primaryScreen();
        QVERIFY(screen);
        const Qt::ScreenOrientation all[] = { Qt::PortraitOrientation, Qt::LandscapeOrientation,
                                              Qt::InvertedPortraitOrientation,
                                              Qt::InvertedLandscapeOrientation };
        for (Qt::ScreenOrientation primary : { Qt::PortraitOrientation, Qt::LandscapeOrientation }) {
            for (Qt::ScreenOrientation o : all) {
                int expected = screen->angleBetween(primary, o);
                expected = ShellState::normalizeAngle(expected);
                QCOMPARE(orientationToAngle(o, primary), expected);
                QCOMPARE(angleToOrientation(expected, primary), o);
            }
        }
        QCOMPARE(orientationToAngle(Qt::PrimaryOrientation, Qt::PortraitOrientation), 0);
    }

    void normalize()
    {
        QCOMPARE(ShellState::normalizeAngle(-90), 270);
        QCOMPARE(ShellState::normalizeAngle(450), 90);
        QCOMPARE(ShellState::normalizeAngle(80), 90);
        QCOMPARE(ShellState::normalizeAngle(359), 0);
    }

    void maliitTable()
    {
        // qt-runner's table for portrait-native phones.
        QCOMPARE(maliitAngle(Qt::PortraitOrientation, true), 0);
        QCOMPARE(maliitAngle(Qt::LandscapeOrientation, true), 90);
        QCOMPARE(maliitAngle(Qt::InvertedPortraitOrientation, true), 180);
        QCOMPARE(maliitAngle(Qt::InvertedLandscapeOrientation, true), 270);
        QCOMPARE(maliitAngle(Qt::PortraitOrientation, false), 270);
    }
};

QTEST_MAIN(TestOrientation)
#include "tst_orientation.moc"
