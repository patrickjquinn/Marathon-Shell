// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's timer-based libiphb stand-in: when a wakeup comes for a
// [mintime, maxtime] range.

#include <QtTest>

#include <poll.h>

#include "iphbd/libiphb.h"

namespace {

// KEEL_IPHB_FALLBACK_SCALE_MS for this test: one "second" lasts 20 ms.
constexpr int kScaleMs = 20;

// Milliseconds until the handle's fd becomes readable, or -1 after timeoutMs.
int msUntilWakeup(iphb_t h, int timeoutMs)
{
    QElapsedTimer t;
    t.start();
    pollfd p{ iphb_get_fd(h), POLLIN, 0 };
    const int rc = ::poll(&p, 1, timeoutMs);
    return rc > 0 ? static_cast<int>(t.elapsed()) : -1;
}

} // namespace

class tst_IphbFallback : public QObject
{
    Q_OBJECT
private slots:
    void initTestCase() { qputenv("KEEL_IPHB_FALLBACK_SCALE_MS", QByteArray::number(kScaleMs)); }
    void waitsForMintime();
    void zeroMintimeWaitsForMaxtime();
    void zeroRangeDisarms();
};

void tst_IphbFallback::waitsForMintime()
{
    iphb_t h = iphb_open(nullptr);
    QVERIFY(h);
    QCOMPARE(iphb_wait2(h, 5, 10, 0, 0), time_t(0));
    const int ms = msUntilWakeup(h, 2000);
    QVERIFY2(ms >= 5 * kScaleMs - 5, qPrintable(QString::number(ms)));
    iphb_close(h);
}

void tst_IphbFallback::zeroMintimeWaitsForMaxtime()
{
    // Before the fix the deadline was "now": a heartbeat re-arming with
    // [0, max] from its own wakeup busy-looped.
    iphb_t h = iphb_open(nullptr);
    QVERIFY(h);
    QCOMPARE(iphb_wait2(h, 0, 10, 0, 0), time_t(0));
    QCOMPARE(msUntilWakeup(h, 5 * kScaleMs), -1);
    const int ms = msUntilWakeup(h, 2000);
    QVERIFY2(ms >= 0, "no wakeup by maxtime");
    iphb_close(h);
}

void tst_IphbFallback::zeroRangeDisarms()
{
    iphb_t h = iphb_open(nullptr);
    QVERIFY(h);
    QCOMPARE(iphb_wait2(h, 0, 0, 0, 0), time_t(0));
    QCOMPARE(msUntilWakeup(h, 10 * kScaleMs), -1);
    iphb_close(h);
}

QTEST_GUILESS_MAIN(tst_IphbFallback)
#include "tst_iphbfallback.moc"
