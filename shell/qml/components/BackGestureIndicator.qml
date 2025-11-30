import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Canvas {
    id: indicator
    width: 100
    height: parent.height
    anchors.left: parent.left
    opacity: 0
    z: 100

    property real progress: 0
    property real maxProgress: 200

    onProgressChanged: {
        opacity = Math.min(progress / 50, 1.0);
        requestPaint();
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        if (progress === 0)
            return;
        var centerY = height / 2;
        var startX = 0;
        var controlX = Math.min(progress * 0.5, 50);
        var endX = Math.min(progress, 80);
        var curveHeight = Math.min(progress * 0.8, 60);

        ctx.beginPath();
        ctx.moveTo(startX, centerY - curveHeight);
        ctx.quadraticCurveTo(controlX, centerY - curveHeight, endX, centerY);
        ctx.quadraticCurveTo(controlX, centerY + curveHeight, startX, centerY + curveHeight);

        var gradient = ctx.createLinearGradient(0, centerY - curveHeight, endX, centerY);
        gradient.addColorStop(0, Qt.rgba(20 / 255, 184 / 255, 166 / 255, 0));
        gradient.addColorStop(1, Qt.rgba(20 / 255, 184 / 255, 166 / 255, 0.6));

        ctx.fillStyle = gradient;
        ctx.fill();

        ctx.strokeStyle = Qt.rgba(20 / 255, 184 / 255, 166 / 255, 0.8);
        ctx.lineWidth = 2;
        ctx.stroke();
    }

    function show(gestureProgress) {
        progress = gestureProgress;
    }

    function hide() {
        progress = 0;
        opacity = 0;
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }
}
