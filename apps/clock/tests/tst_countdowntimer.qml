import QtQuick
import QtTest
import "../models"

TestCase {
    name: "CountdownTimer"

    property real t: 0

    Component {
        id: countdown
        CountdownTimer {
            now: () => t
        }
    }
    SignalSpy {
        id: finishedSpy
        signalName: "finished"
    }

    function test_setThenStart() {
        const c = createTemporaryObject(countdown, this);
        c.set(300);
        compare(c.remaining, 300);
        compare(c.total, 300);
        verify(!c.running);
        t = 0;
        c.start();
        verify(c.running);
        t = 61500;
        c.update();
        compare(c.remaining, 239);
    }

    function test_pauseKeepsRemaining() {
        const c = createTemporaryObject(countdown, this);
        c.set(60);
        t = 0;
        c.start();
        t = 10000;
        c.pause();
        compare(c.remaining, 50);
        t = 99000;
        c.update();
        compare(c.remaining, 50);
        c.start();
        t = 109000;
        c.update();
        compare(c.remaining, 40);
    }

    function test_finishes() {
        const c = createTemporaryObject(countdown, this);
        finishedSpy.target = c;
        finishedSpy.clear();
        c.set(5);
        t = 0;
        c.start();
        t = 6000;
        c.update();
        compare(c.remaining, 0);
        verify(!c.running);
        compare(finishedSpy.count, 1);
        c.update();
        compare(finishedSpy.count, 1);
    }

    function test_startNeedsTime() {
        const c = createTemporaryObject(countdown, this);
        c.start();
        verify(!c.running);
    }

    function test_reset() {
        const c = createTemporaryObject(countdown, this);
        c.set(60);
        c.start();
        c.reset();
        verify(!c.running);
        compare(c.remaining, 0);
        compare(c.total, 0);
    }

    function test_setIgnoredWhileRunning() {
        const c = createTemporaryObject(countdown, this);
        c.set(60);
        c.start();
        c.set(5);
        compare(c.total, 60);
    }

    function test_snapshotRestoresRunning() {
        const c = createTemporaryObject(countdown, this);
        c.set(60);
        t = 0;
        c.start();
        const saved = JSON.parse(JSON.stringify(c.snapshot()));
        const r = createTemporaryObject(countdown, this);
        t = 20000;
        compare(r.restore(saved), -1);
        verify(r.running);
        compare(r.total, 60);
        compare(r.remaining, 40);
    }

    function test_snapshotRestoresPaused() {
        const c = createTemporaryObject(countdown, this);
        c.set(60);
        t = 0;
        c.start();
        t = 15000;
        c.pause();
        const r = createTemporaryObject(countdown, this);
        t = 999000;
        r.restore(JSON.parse(JSON.stringify(c.snapshot())));
        verify(!r.running);
        compare(r.remaining, 45);
        compare(r.total, 60);
    }

    function test_restoreReportsATimerThatEndedWhileClosed() {
        const c = createTemporaryObject(countdown, this);
        c.set(60);
        t = 0;
        c.start();
        const saved = JSON.parse(JSON.stringify(c.snapshot()));
        const r = createTemporaryObject(countdown, this);
        finishedSpy.target = r;
        finishedSpy.clear();
        t = 90000;
        compare(r.restore(saved), 60000);
        verify(!r.running);
        compare(r.remaining, 0);
        compare(finishedSpy.count, 0);
    }

    SignalSpy {
        id: editedSpy
        signalName: "edited"
    }

    function test_editsAreSignalled() {
        const c = createTemporaryObject(countdown, this);
        editedSpy.target = c;
        editedSpy.clear();
        c.set(1);
        t = 0;
        c.start();
        t = 500;
        c.update();
        compare(editedSpy.count, 2);
        t = 2000;
        c.update();
        compare(editedSpy.count, 3);
        c.reset();
        compare(editedSpy.count, 4);
    }
}
