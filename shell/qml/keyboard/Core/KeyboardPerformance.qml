// Marathon Keyboard - Performance Optimizations
// QML-based optimizations for zero-latency input
pragma Singleton
import QtQuick

QtObject {
    id: keyboardPerf

    /**
     * CRITICAL OPTIMIZATION 1: Pre-render key glyphs
     * Cache rendered text to avoid re-layout on every frame
     */
    readonly property bool useTextMetricsCache: true

    /**
     * CRITICAL OPTIMIZATION 2: Batch property updates
     * Use PropertyAnimation instead of direct property changes
     */
    readonly property int keyPressAnimationDuration: 50 // ms

    /**
     * CRITICAL OPTIMIZATION 3: Lazy load prediction bar
     * Only create when needed
     */
    readonly property bool lazyLoadPredictions: true

    /**
     * CRITICAL OPTIMIZATION 4: Touch event priority
     * Process keyboard touches before other UI elements
     */
    readonly property int touchEventPriority: Qt.HighEventPriority

    /**
     * CRITICAL OPTIMIZATION 5: Minimize QML re-evaluation
     * Use const/readonly where possible
     */
    readonly property bool optimizeBindings: true

    /**
     * Performance monitoring
     */
    property var frameTimings: []
    property real averageFrameTime: 16.67 // 60 FPS target

    function recordFrameTime(time) {
        frameTimings.push(time);
        if (frameTimings.length > 100) {
            frameTimings.shift();
        }

        let sum = 0;
        for (let i = 0; i < frameTimings.length; i++) {
            sum += frameTimings[i];
        }
        averageFrameTime = sum / frameTimings.length;

        if (averageFrameTime > 16.67) {
            console.warn("[KeyboardPerf] Frame time exceeded 16.67ms:", averageFrameTime);
        }
    }

    /**
     * Touch latency monitoring
     */
    property var touchLatencies: []
    property real averageTouchLatency: 0

    function recordTouchLatency(latency) {
        touchLatencies.push(latency);
        if (touchLatencies.length > 50) {
            touchLatencies.shift();
        }

        let sum = 0;
        for (let i = 0; i < touchLatencies.length; i++) {
            sum += touchLatencies[i];
        }
        averageTouchLatency = sum / touchLatencies.length;

        if (averageTouchLatency > 5) {
            console.warn("[KeyboardPerf] Touch latency exceeded 5ms:", averageTouchLatency);
        }
    }
}
