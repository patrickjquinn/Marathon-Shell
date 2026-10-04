import MarathonUI.Theme
import QtQuick

// Five stars filled to `value` (0-5). Phosphor ships outline stars only, so
// the shape is painted; a fractional value fills the last star partway.
Canvas {
    id: stars

    property real value: 0
    property int starSize: 12
    property color color: MColors.textSecondary
    readonly property int gap: Math.max(1, Math.round(starSize * 0.15))

    function starPath(ctx, x) {
        const r = starSize / 2;
        const cx = x + r;
        const cy = r;
        ctx.beginPath();
        for (let i = 0; i < 10; i++) {
            const radius = i % 2 === 0 ? r : r * 0.45;
            const a = -Math.PI / 2 + i * Math.PI / 5;
            const px = cx + radius * Math.cos(a);
            const py = cy + radius * Math.sin(a);
            if (i === 0)
                ctx.moveTo(px, py);
            else
                ctx.lineTo(px, py);
        }
        ctx.closePath();
    }

    implicitWidth: starSize * 5 + gap * 4
    implicitHeight: starSize
    onValueChanged: requestPaint()
    onColorChanged: requestPaint()
    onStarSizeChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        ctx.fillStyle = color;
        for (let i = 0; i < 5; i++) {
            const x = i * (starSize + gap);
            ctx.globalAlpha = 0.22;
            starPath(ctx, x);
            ctx.fill();
            const fill = Math.max(0, Math.min(1, value - i));
            if (fill <= 0)
                continue;
            ctx.save();
            ctx.beginPath();
            ctx.rect(x, 0, starSize * fill, starSize);
            ctx.clip();
            ctx.globalAlpha = 1;
            starPath(ctx, x);
            ctx.fill();
            ctx.restore();
        }
    }
}
