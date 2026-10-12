import QtQuick
import QtTest
import "../models"

TestCase {
    name: "CountdownTimer"

    property real t: 0

    Component {
        id: countdown
        CountdownTimer { now: () => t }
    }
    SignalSpy { id: finishedSpy; signalName: "finished" }

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
}
