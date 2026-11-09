pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property var profiles: [
        {
            value: "performance",
            title: qsTr("Performance"),
            description: qsTr("Fastest, uses more battery")
        },
        {
            value: "balanced",
            title: qsTr("Balanced"),
            description: qsTr("Balances speed and battery life")
        },
        {
            value: "power-saver",
            title: qsTr("Power saver"),
            description: qsTr("Slower, makes the battery last longer")
        }
    ]
    readonly property bool hasBatteryLevel: Power.batteryLevel >= 0
    readonly property int historyHours: period.currentIndex === 1 ? 24 * 7 : 24
    // UPower's draw while on battery, over the period.
    readonly property real averageDraw: {
        const r = Power.rateHistory;
        let sum = 0, n = 0;
        for (let i = 1; i < r.length; i += 2)
            if (r[i] > 0) {
                sum += r[i];
                n++;
            }
        return n > 0 ? sum / n : 0;
    }

    onStatusChanged: if (status === PageStatus.Active)
        Power.loadHistory(historyHours)

    function setProfile(value) {
        if (value === "power-saver") {
            Power.setPowerSaveMode(true);
            return;
        }
        if (Power.isPowerSaveMode)
            Power.setPowerSaveMode(false);
        Power.setPowerProfile(value);
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Battery")
            }
            Label {
                objectName: "levelLabel"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.hasBatteryLevel ? qsTr("%1%").arg(Power.batteryLevel) : qsTr("Battery level unavailable")
                font.pixelSize: page.hasBatteryLevel ? Theme.fontSizeHuge : Theme.fontSizeLarge
                color: page.hasBatteryLevel ? Theme.highlightColor : Theme.secondaryHighlightColor
            }
            Label {
                width: parent.width
                visible: page.hasBatteryLevel
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Estimated remaining charge")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                objectName: "statusLabel"
                width: parent.width
                visible: page.hasBatteryLevel || Power.isCharging || Power.isPluggedIn
                horizontalAlignment: Text.AlignHCenter
                text: Logic.batteryStatus(Power.isCharging, Power.isPluggedIn, Power.estimatedBatteryTime)
                color: Theme.secondaryHighlightColor
            }
            Item {
                width: 1
                height: Theme.paddingLarge
            }
            // Power saver is the power-saver profile plus the top menu's Battery saver tile state.
            ComboBox {
                objectName: "profileCombo"
                width: parent.width
                visible: Power.powerProfilesSupported
                label: qsTr("Power profile")
                description: currentIndex >= 0 ? page.profiles[currentIndex].description : ""
                Binding on currentIndex {
                    value: page.profiles.findIndex(p => p.value === (Power.isPowerSaveMode ? "power-saver" : Power.powerProfile))
                }
                menu: ContextMenu {
                    Repeater {
                        model: page.profiles

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: page.setProfile(modelData.value)
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Battery history")
            }
            ComboBox {
                id: period

                objectName: "historyPeriod"
                width: parent.width
                label: qsTr("Period")
                currentIndex: 0
                onCurrentIndexChanged: Power.loadHistory(page.historyHours)
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Last 24 hours")
                    }
                    MenuItem {
                        text: qsTr("Last 7 days")
                    }
                }
            }
            // Charge over time, and the power drawn beneath it: drawn once
            // per read, from what UPower already keeps.
            Canvas {
                id: graph

                objectName: "historyGraph"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeHuge * 1.6
                renderStrategy: Canvas.Cooperative
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const w = width, h = height;
                    const now = Date.now() / 1000;
                    const from = now - page.historyHours * 3600;
                    const x = t => (t - from) / (now - from) * w;
                    ctx.strokeStyle = Theme.rgba(Theme.primaryColor, 0.15);
                    ctx.lineWidth = 1;
                    for (const f of [0, 0.5, 1]) {
                        ctx.beginPath();
                        ctx.moveTo(0, Math.round(f * (h - 1)) + 0.5);
                        ctx.lineTo(w, Math.round(f * (h - 1)) + 0.5);
                        ctx.stroke();
                    }
                    const rate = Power.rateHistory;
                    let peak = 0;
                    for (let i = 1; i < rate.length; i += 2)
                        peak = Math.max(peak, rate[i]);
                    if (peak > 0) {
                        ctx.strokeStyle = Theme.rgba(Theme.secondaryColor, 0.6);
                        ctx.beginPath();
                        for (let i = 0; i < rate.length; i += 2) {
                            const px = x(rate[i]), py = h - rate[i + 1] / peak * h * 0.45;
                            if (i === 0)
                                ctx.moveTo(px, py);
                            else
                                ctx.lineTo(px, py);
                        }
                        ctx.stroke();
                    }
                    const charge = Power.chargeHistory;
                    if (charge.length < 2)
                        return;
                    const level = i => h - charge[i + 1] / 100 * h;
                    ctx.beginPath();
                    ctx.moveTo(Math.max(0, x(charge[0])), level(0));
                    for (let i = 2; i < charge.length; i += 2)
                        ctx.lineTo(x(charge[i]), level(i));
                    ctx.lineTo(w, level(charge.length - 2));
                    ctx.strokeStyle = Theme.highlightColor;
                    ctx.lineWidth = 2;
                    ctx.stroke();
                    ctx.lineTo(w, h);
                    ctx.lineTo(Math.max(0, x(charge[0])), h);
                    ctx.closePath();
                    ctx.fillStyle = Theme.rgba(Theme.highlightColor, 0.15);
                    ctx.fill();
                }

                Connections {
                    function onHistoryChanged() {
                        graph.requestPaint();
                    }

                    target: Power
                }
            }
            Item {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeExtraSmall

                Label {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.historyHours > 24 ? qsTr("7 days ago") : qsTr("24 hours ago")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
                Label {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Now")
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeExtraSmall
                }
            }
            DetailItem {
                objectName: "averageDraw"
                visible: page.averageDraw > 0
                label: qsTr("Average power draw")
                value: qsTr("%1 W").arg(page.averageDraw.toLocaleString(Qt.locale(), "f", 2))
            }
        }

        VerticalScrollDecorator {}
    }
}
