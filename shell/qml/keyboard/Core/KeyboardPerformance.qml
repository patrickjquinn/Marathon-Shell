pragma Singleton
import QtQuick

QtObject {
    id: keyboardPerf

    readonly property bool useTextMetricsCache: true
    readonly property int keyPressAnimationDuration: 50
    readonly property bool lazyLoadPredictions: true
    readonly property int touchEventPriority: Qt.HighEventPriority
    readonly property bool optimizeBindings: true
    property var frameTimings: []
    property real averageFrameTime: 16.67
    property var touchLatencies: []
    property real averageTouchLatency: 0

    function recordFrameTime(time) {
        frameTimings.push(time);
        if (frameTimings.length > 100)
            frameTimings.shift();

        let sum = 0;
        for (let i = 0; i < frameTimings.length; i++)
            sum += frameTimings[i];
        averageFrameTime = sum / frameTimings.length;
        if (averageFrameTime > 16.67)
            console.warn("[KeyboardPerf] Frame time exceeded 16.67ms:", averageFrameTime);
    }

    function recordTouchLatency(latency) {
        touchLatencies.push(latency);
        if (touchLatencies.length > 50)
            touchLatencies.shift();

        let sum = 0;
        for (let i = 0; i < touchLatencies.length; i++)
            sum += touchLatencies[i];
        averageTouchLatency = sum / touchLatencies.length;
        if (averageTouchLatency > 5)
            console.warn("[KeyboardPerf] Touch latency exceeded 5ms:", averageTouchLatency);
    }
}
