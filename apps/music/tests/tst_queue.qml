import QtQuick
import QtTest
import "../Queue.js" as Queue

TestCase {
    name: "Queue"

    function test_nextInOrder() {
        compare(Queue.next(3, 0, false, false, 0), 1);
        compare(Queue.next(3, 1, false, false, 0), 2);
    }

    function test_nextAtEndStopsWithoutWrap() {
        compare(Queue.next(3, 2, false, false, 0), -1);
    }

    function test_nextAtEndWraps() {
        compare(Queue.next(3, 2, false, true, 0), 0);
    }

    function test_emptyQueue() {
        compare(Queue.next(0, -1, false, true, 0), -1);
        compare(Queue.previous(0, -1), -1);
    }

    function test_shuffleNeverRepeatsCurrent() {
        for (let r = 0; r < 1; r += 0.05)
            verify(Queue.next(4, 1, true, false, r) !== 1);
        compare(Queue.next(1, 0, true, false, 0.5), 0);
    }

    function test_previousWraps() {
        compare(Queue.previous(3, 1), 0);
        compare(Queue.previous(3, 0), 2);
    }
}
