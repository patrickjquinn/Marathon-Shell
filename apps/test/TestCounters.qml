// pragma Singleton — visible from any .qml file that `imports MarathonApp.Test`.
//
// Test-app counter state. Lives outside the page hierarchy so child .qml
// pages can `TestCounters.passedTests++` without dragging the outer
// TestApp.qml's id into their scope (QML ids do not bubble across
// separately-compiled components, hence the page-by-page `testApp` prop
// attempts in earlier revisions reading as undefined).
pragma Singleton

import QtQuick

QtObject {
    property int passedTests: 0
    property int failedTests: 0
    property int totalTests: 0

    function pass(name) {
        passedTests++;
        totalTests++;
        if (name)
            console.log("[TestCounters] PASS:", name);
    }

    function fail(name) {
        failedTests++;
        totalTests++;
        if (name)
            console.log("[TestCounters] FAIL:", name);
    }

    function reset() {
        passedTests = 0;
        failedTests = 0;
        totalTests = 0;
    }
}
