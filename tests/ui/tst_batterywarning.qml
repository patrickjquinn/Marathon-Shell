import QtQuick
import QtTest
import "../../shell/qml/core/BatteryWarning.js" as BatteryWarning

TestCase {
    name: "BatteryWarning"

    function run(levels, pluggedIn) {
        const state = { warnedAt: 101, last: -1 };
        return levels.map(l => BatteryWarning.check(state, l, pluggedIn)).filter(b => b > 0);
    }

    function test_onceForEachBandOnTheWayDown() {
        compare(run([22, 21, 20, 19, 15, 11, 10, 9, 6, 5, 4], false), [20, 10, 5]);
    }

    // A gauge with an "Unknown" status: UPower calls it unplugged between
    // the percents a charger adds.
    function test_chargingWithoutAPlugStateIsQuiet() {
        compare(run([9, 10, 11, 12, 13, 14], false), [10]);
    }

    function test_jitterWhileChargingIsQuiet() {
        compare(run([9, 10, 9, 10, 11, 10, 12, 11], false), [10]);
    }

    function test_warnsAgainAfterACharge() {
        compare(run([19, 25, 30, 21, 20], false), [20, 20]);
    }

    function test_quietWhilePluggedIn() {
        compare(run([20, 10, 5], true), []);
    }
}
