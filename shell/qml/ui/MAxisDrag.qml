import QtQuick

// A drag along one of its item's own axes, however the scene is turned.
// DragHandler takes its start threshold along xAxis/yAxis in scene
// coordinates, and on a panel mounted sideways (the MP01) the compositor
// turns the scene, so the item's x runs along the scene's y: each press
// enables the scene axis that lies along `horizontal`. Read the drag with
// travel() and speed(), in the item's coordinates.
DragHandler {
    id: root

    property bool horizontal: true

    // Where a scene point lies along the axis, in the item's coordinates.
    function along(scenePoint) {
        const p = parent.mapFromItem(null, scenePoint.x, scenePoint.y);
        return horizontal ? p.x : p.y;
    }
    // Along the axis since the press, px.
    function travel() {
        return along(centroid.scenePosition) - along(centroid.scenePressPosition);
    }
    // Along the axis, px/s.
    function speed() {
        const v = centroid.velocity;
        return along(Qt.point(v.x, v.y)) - along(Qt.point(0, 0));
    }
    function orient() {
        const o = parent.mapToItem(null, 0, 0);
        const x = parent.mapToItem(null, 1, 0);
        const sideways = Math.abs(x.y - o.y) > Math.abs(x.x - o.x);
        xAxis.enabled = horizontal !== sideways;
        yAxis.enabled = horizontal === sideways;
        console.debug(log, "press", parent, centroid.scenePosition, "sideways", sideways);
    }

    // QT_LOGGING_RULES or qtlogging.ini: marathon.axisdrag.debug=true.
    readonly property LoggingCategory log: LoggingCategory {
        name: "marathon.axisdrag"
        defaultLogLevel: LoggingCategory.Warning
    }

    target: null
    xAxis.enabled: horizontal
    yAxis.enabled: !horizontal

    // A connection, not a handler: users have their own onCentroidChanged.
    property Connections _orient: Connections {
        function onCentroidChanged() {
            if (!root.active)
                root.orient();
        }

        function onActiveChanged() {
            console.debug(root.log, root.active ? "active" : "released", root.parent, root.centroid.scenePosition, "travel", root.travel(), "speed", root.speed());
        }

        target: root
    }
}
