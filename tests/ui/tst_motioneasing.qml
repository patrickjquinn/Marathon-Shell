import QtQuick
import QtTest
import MarathonOS.RealMotion as Real

TestCase {
    id: root

    name: "MotionEasing"

    property real value: 0

    function sample(curve, progress) {
        anim.easing.bezierCurve = curve;
        controller.reload();
        controller.progress = progress;
        return root.value;
    }

    function curves() {
        const list = [
            {
                tag: "easingStandardCurve",
                curve: Real.MMotion.easingStandardCurve
            },
            {
                tag: "easingDecelerateCurve",
                curve: Real.MMotion.easingDecelerateCurve
            },
            {
                tag: "predictiveBackCurve",
                curve: Real.MMotion.predictiveBackCurve
            }
        ];
        for (const role in Real.MMotion.roles)
            list.push({
                tag: role,
                curve: Real.MMotion.easingCurveFor(role)
            });
        return list;
    }

    function test_curveIsQtBezier_data() {
        return curves();
    }

    function test_curveIsQtBezier(data) {
        compare(data.curve.length % 6, 0, "Qt wants (c1, c2, end) groups");
        compare(data.curve[data.curve.length - 2], 1);
        compare(data.curve[data.curve.length - 1], 1);
    }

    function test_curveIsNotLinear_data() {
        return curves();
    }

    function test_curveIsNotLinear(data) {
        let deviation = 0;
        for (let p = 0.1; p < 1; p += 0.1)
            deviation = Math.max(deviation, Math.abs(sample(data.curve, p) - p));
        verify(deviation > 0.05, data.tag + " deviates " + deviation.toFixed(3));
    }

    function test_modalOvershoots() {
        let peak = 0;
        for (let p = 0.05; p < 1; p += 0.05)
            peak = Math.max(peak, sample(Real.MMotion.easingCurveFor("modal"), p));
        verify(peak > 1.05, "modal peaks at " + peak.toFixed(3));
    }

    AnimationController {
        id: controller

        animation: NumberAnimation {
            id: anim

            target: root
            property: "value"
            from: 0
            to: 1
            duration: 1000
            easing.type: Easing.Bezier
        }
    }
}
