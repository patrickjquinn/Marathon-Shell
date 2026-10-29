import QtQuick
import QtTest
import "../models"

TestCase {
    name: "Stopwatch"

    property real t: 0

    Component {
        id: stopwatch
        Stopwatch {
            now: () => t
        }
    }

    function test_startStopAccumulates() {
        const s = createTemporaryObject(stopwatch, this);
        t = 1000;
        s.start();
        verify(s.running);
        t = 3500;
        s.stop();
        verify(!s.running);
        compare(s.elapsed, 2500);
        t = 10000;
        s.start();
        t = 10500;
        s.update();
        compare(s.elapsed, 3000);
    }

    function test_lapsAreCumulative() {
        const s = createTemporaryObject(stopwatch, this);
        t = 0;
        s.start();
        t = 1200;
        s.lap();
        t = 2000;
        s.lap();
        compare(s.laps, [1200, 2000]);
    }

    function test_resetClears() {
        const s = createTemporaryObject(stopwatch, this);
        t = 0;
        s.start();
        t = 500;
        s.lap();
        s.stop();
        s.reset();
        compare(s.elapsed, 0);
        compare(s.laps, []);
        verify(!s.running);
    }

    function test_ticksWhileRunning() {
        const s = createTemporaryObject(stopwatch, this, {
            now: () => Date.now()
        });
        s.start();
        tryVerify(() => s.elapsed > 0, 1000);
    }

    function test_snapshotRestores() {
        const s = createTemporaryObject(stopwatch, this);
        t = 1000;
        s.start();
        t = 2000;
        s.lap();
        const saved = JSON.parse(JSON.stringify(s.snapshot()));
        const r = createTemporaryObject(stopwatch, this);
        t = 5000;
        r.restore(saved);
        verify(r.running);
        compare(r.elapsed, 4000);
        compare(r.laps, [1000]);
        r.restore({});
        verify(!r.running);
        compare(r.elapsed, 0);
    }

    SignalSpy {
        id: editedSpy
        signalName: "edited"
    }

    function test_editsAreSignalled() {
        const s = createTemporaryObject(stopwatch, this);
        editedSpy.target = s;
        editedSpy.clear();
        s.start();
        s.lap();
        s.stop();
        s.reset();
        compare(editedSpy.count, 4);
    }
}
