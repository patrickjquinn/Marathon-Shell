// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// ShellState: the keyboard rectangle the app reports over the peer bus, and
// the keyboard height both backends use for --follow-keyboard.

#include <QtTest>

#include "core/shellstate.h"

using namespace keel;

class TestShellState : public QObject
{
    Q_OBJECT
private slots:
    void keyboardHeight_data()
    {
        QTest::addColumn<int>("contentOrientation");
        QTest::addColumn<int>("expected");
        // Maliit's rectangle is in the portrait screen's coordinates: a
        // 1080 x 600 strip at the bottom in portrait, a 500 x 1920 strip
        // along the side when the content is landscape.
        QTest::newRow("portrait") << 0 << 600;
        QTest::newRow("inverted portrait") << 180 << 600;
        QTest::newRow("landscape") << 90 << 500;
        QTest::newRow("inverted landscape") << 270 << 500;
    }
    void keyboardHeight()
    {
        QFETCH(int, contentOrientation);
        QFETCH(int, expected);
        ShellState state;
        state.setContentOrientation(contentOrientation);
        QCOMPARE(state.keyboardHeight(), 0);
        const bool portrait = contentOrientation % 180 == 0;
        state.setKeyboardRect(true, portrait ? QRect(0, 1320, 1080, 600)
                                             : QRect(580, 0, 500, 1920));
        QCOMPARE(state.keyboardHeight(), expected);
        state.setKeyboardRect(false, QRect());
        QCOMPARE(state.keyboardHeight(), 0);
    }

    void negativeRectIgnored_data()
    {
        QTest::addColumn<QRect>("rect");
        QTest::newRow("negative height") << QRect(0, 0, 1080, -600);
        QTest::newRow("negative width") << QRect(0, 0, -1080, 600);
    }
    void negativeRectIgnored()
    {
        QFETCH(QRect, rect);
        ShellState state;
        QSignalSpy changed(&state, &ShellState::keyboardRectChanged);
        state.setKeyboardRect(true, QRect(0, 1320, 1080, 600));
        QCOMPARE(changed.count(), 1);
        // A peer sending garbage must not grow the app beyond the output.
        state.setKeyboardRect(true, rect);
        QCOMPARE(changed.count(), 1);
        QCOMPARE(state.keyboardRect(), QRect(0, 1320, 1080, 600));
        QCOMPARE(state.keyboardHeight(), 600);
        // Hiding still works whatever the rectangle.
        state.setKeyboardRect(false, rect);
        QVERIFY(!state.keyboardActive());
        QCOMPARE(state.keyboardHeight(), 0);
    }
};

QTEST_GUILESS_MAIN(TestShellState)
#include "tst_shellstate.moc"
