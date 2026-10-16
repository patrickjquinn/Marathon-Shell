pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Shapes
import Sailfish.Silica 1.0 as Silica
import "../core/Weather.js" as Weather

// The coming hours: a temperature curve over each hour's sky, its rain as
// bars under the curve, and the hour.
Item {
    id: chart

    property var hours: []
    property int offset: 0
    property bool fahrenheit: false
    property bool twelveHour: false
    property real curveHeight: Silica.Theme.itemSizeSmall

    readonly property real columnWidth: hours.length > 0 ? width / hours.length : 0
    readonly property real labelHeight: Silica.Theme.fontSizeExtraSmall * 1.5
    readonly property var temps: hours.map(h => h.temperature)
    readonly property real low: Math.min.apply(null, temps)
    readonly property real high: Math.max.apply(null, temps)
    readonly property var points: hours.map((h, i) => Qt.point((i + 0.5) * columnWidth, yFor(h.temperature)))

    function yFor(t) {
        return labelHeight + curveHeight * (1 - (t - low) / Math.max(2, high - low));
    }

    // Catmull-Rom through the points, flat out to both edges.
    function curve(pts) {
        if (pts.length === 0)
            return [];
        const out = [Qt.point(0, pts[0].y)];
        for (let i = 0; i < pts.length - 1; ++i) {
            const p0 = pts[Math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[Math.min(pts.length - 1, i + 2)];
            for (let s = 0; s < 8; ++s) {
                const t = s / 8, t2 = t * t, t3 = t2 * t;
                out.push(Qt.point(0.5 * (2 * p1.x + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3), 0.5 * (2 * p1.y + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)));
            }
        }
        out.push(pts[pts.length - 1]);
        out.push(Qt.point(width, pts[pts.length - 1].y));
        return out;
    }

    implicitHeight: labelHeight + curveHeight + Silica.Theme.paddingMedium + columns.height

    // Rain: 4 mm in an hour fills half the curve's height.
    Repeater {
        model: chart.hours

        Rectangle {
            required property var modelData
            required property int index

            readonly property real amount: Math.min(4, modelData.precipitation || 0)

            x: index * chart.columnWidth + chart.columnWidth * 0.2
            width: chart.columnWidth * 0.6
            height: amount / 4 * chart.curveHeight * 0.5
            y: chart.labelHeight + chart.curveHeight - height
            visible: amount >= 0.1
            radius: Silica.Theme.paddingSmall / 2
            color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.35)
        }
    }

    Shape {
        anchors.fill: parent

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                y1: chart.labelHeight
                y2: chart.labelHeight + chart.curveHeight

                GradientStop {
                    position: 0
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.22)
                }
                GradientStop {
                    position: 1
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0)
                }
            }
            startX: 0
            startY: chart.labelHeight + chart.curveHeight

            PathPolyline {
                path: chart.curve(chart.points)
            }
            PathLine {
                x: chart.width
                y: chart.labelHeight + chart.curveHeight
            }
        }
        ShapePath {
            strokeColor: Silica.Theme.highlightColor
            strokeWidth: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            PathPolyline {
                path: chart.curve(chart.points)
            }
        }
    }

    Repeater {
        model: chart.hours

        Silica.Label {
            required property var modelData
            required property int index

            x: index * chart.columnWidth
            width: chart.columnWidth
            y: (chart.points[index] || Qt.point(0, chart.labelHeight)).y - height - Silica.Theme.paddingSmall / 2
            horizontalAlignment: Text.AlignHCenter
            text: Weather.temperature(modelData.temperature, chart.fahrenheit)
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
            color: index === 0 ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
        }
    }

    Row {
        id: columns

        y: chart.labelHeight + chart.curveHeight + Silica.Theme.paddingMedium

        Repeater {
            model: chart.hours

            Column {
                id: column

                required property var modelData
                required property int index

                width: chart.columnWidth
                spacing: Silica.Theme.paddingSmall / 2

                GlyphIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: Weather.glyph(column.modelData.symbol, column.modelData.is_day)
                    size: Silica.Theme.iconSizeSmallPlus
                    color: Silica.Theme.primaryColor
                }
                Silica.Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    // The chance of rain, when it's worth a glance.
                    text: (column.modelData.precipitation_probability || 0) >= 20 ? column.modelData.precipitation_probability + "%" : " "
                    font.pixelSize: Silica.Theme.fontSizeTiny
                    color: Silica.Theme.highlightColor
                }
                Silica.Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: column.index === 0 ? qsTr("Now") : Weather.hour(column.modelData.time, chart.offset, chart.twelveHour)
                    font.pixelSize: Silica.Theme.fontSizeTiny
                    color: Silica.Theme.secondaryColor
                }
            }
        }
    }
}
