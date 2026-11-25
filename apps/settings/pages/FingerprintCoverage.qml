import QtQuick
import Sailfish.Silica 1.0

// A fingerprint's ridges, lit from the core outwards as the touches of an
// enrolment cover more of the finger. Painted again only when that changes.
Canvas {
    id: root

    // 0 to 1: the share of the touches taken.
    property real coverage: 0
    property color litColor: Theme.highlightColor
    property color restColor: Theme.rgba(Theme.primaryColor, Theme.opacityLow)
    property bool animated: true
    property real shown: coverage
    readonly property int ridges: 9

    // The ridges of one finger: an ellipse open at the bottom, as a loop
    // print is, with a break in every other ridge where a ridge would end.
    function segments(i) {
        const gap = (34 + (ridges - 1 - i) * 5) * Math.PI / 180;
        const from = Math.PI / 2 + gap;
        const to = Math.PI * 5 / 2 - gap;
        if (i % 2 === 0)
            return [[from, to]];
        const at = Math.PI * (1.25 + 0.5 * ((i * 37) % 11) / 11);
        const half = 0.1;
        return [[from, at - half], [at + half, to]];
    }

    function strokeArc(ctx, cx, cy, r, a0, a1, color, weight) {
        if (a1 - a0 <= 0.001)
            return;
        const steps = Math.max(2, Math.ceil((a1 - a0) / 0.05));
        ctx.strokeStyle = color;
        ctx.lineWidth = weight;
        ctx.beginPath();
        for (let k = 0; k <= steps; ++k) {
            const a = a0 + (a1 - a0) * k / steps;
            const x = cx + r * Math.cos(a);
            const y = cy + 1.22 * r * Math.sin(a);
            if (k === 0)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
        }
        ctx.stroke();
    }

    implicitWidth: Theme.itemSizeHuge * 2
    implicitHeight: implicitWidth * 1.2
    Accessible.role: Accessible.ProgressBar
    Accessible.name: qsTr("Fingerprint coverage")
    onShownChanged: requestPaint()
    onLitColorChanged: requestPaint()
    onRestColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const s = Math.min(width, height / 1.2);
        const cx = width / 2;
        const cy = height * 0.53;
        // Lit ridges are heavier too, so the progress reads on a grey e-paper
        // panel, where the two colours come out alike.
        const thin = Math.max(1, Math.round(s * 0.012));
        ctx.lineCap = "round";
        // Inner ridges fill first; the one being filled grows along its arc.
        const lit = Math.max(0, Math.min(1, shown)) * ridges;
        for (let i = 0; i < ridges; ++i) {
            const r = s * (0.06 + i * 0.048);
            const part = Math.max(0, Math.min(1, lit - i));
            const all = segments(i);
            const from = all[0][0];
            const split = from + (all[all.length - 1][1] - from) * part;
            for (const seg of all) {
                strokeArc(ctx, cx, cy, r, seg[0], Math.min(seg[1], split), litColor, 2 * thin);
                strokeArc(ctx, cx, cy, r, Math.max(seg[0], split), seg[1], restColor, thin);
            }
        }
    }

    Behavior on shown {
        enabled: root.animated

        NumberAnimation {
            duration: 260
            easing.type: Easing.OutCubic
        }
    }
}
