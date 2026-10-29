import QtQuick
import QtTest
import "../../shell/qml/core/LauncherGrid.js" as LauncherGrid

TestCase {
    name: "LauncherGrid"
    when: labelFont.status === FontLoader.Ready

    // Width and Silica pixel ratio before the person's interface size:
    // HackberryPi and Zinwa Q25 at 254 dpi, PinePhone, Librem 5 at 287 dpi,
    // QEMU at 296 dpi, OnePlus 6.
    readonly property var devices: [
        {
            "name": "HackberryPi",
            "width": 720,
            "ratio": 254 / 160 * 390 / 540
        },
        {
            "name": "PinePhone",
            "width": 720,
            "ratio": 1.2
        },
        {
            "name": "Librem 5",
            "width": 720,
            "ratio": 287 / 160 * 390 / 540
        },
        {
            "name": "QEMU",
            "width": 720,
            "ratio": 296 / 160 * 390 / 540
        },
        {
            "name": "OnePlus 6",
            "width": 1080,
            "ratio": 1.8
        }
    ]
    readonly property var scales: [0.9, 1.0, 1.1, 1.2, 1.3]
    readonly property var names: ["Calendar", "Calculator", "App Store", "Messages", "Settings", "Terminal"]

    // AmbienceService::silicaPixelRatio
    function pixelRatio(device, scale) {
        return Math.round(device.ratio * scale * 20) / 20;
    }

    // Keel's Theme on a phone at that ratio, as MarathonAppGrid lays out its
    // labels: page margins, then a column each less Theme.paddingSmall.
    function labelWidth(device, ratio, columns) {
        const measured = ratio === 1.5;
        const margin = Math.max(measured ? 40 : Math.round(24 * ratio), Math.round(24 * Math.max(1, device.width / 540)));
        return (device.width - 2 * margin) / columns - (measured ? 10 : Math.round(6 * ratio));
    }

    FontLoader {
        id: labelFont

        source: "../../marathon-fonts/source-sans-3/SourceSans3-Regular.ttf"
    }

    TextMetrics {
        id: metrics

        font.family: labelFont.name
    }

    function test_fiveColumnsAtDefaultAndSmallerSizes() {
        for (const device of devices)
            for (const scale of [0.9, 1.0])
                compare(LauncherGrid.columns(device.width, pixelRatio(device, scale), 0), 5, device.name + " " + scale);
    }

    function test_largerSizesDropColumns() {
        const expected = {
            "HackberryPi": [5, 5, 5, 5, 4],
            "PinePhone": [5, 5, 5, 4, 4],
            "Librem 5": [5, 5, 4, 4, 4],
            "QEMU": [5, 5, 4, 4, 3],
            "OnePlus 6": [5, 5, 5, 4, 4]
        };
        for (const device of devices)
            for (let i = 0; i < scales.length; ++i)
                compare(LauncherGrid.columns(device.width, pixelRatio(device, scales[i]), 0), expected[device.name][i], device.name + " " + scales[i]);
    }

    // Common names on one line at Theme.fontSizeTiny, measured in Source Sans 3
    // Regular, wider than the Light the launcher sets them in.
    function test_labelsFitOnOneLine() {
        for (const device of devices) {
            for (const scale of scales) {
                const ratio = pixelRatio(device, scale);
                const width = labelWidth(device, ratio, LauncherGrid.columns(device.width, ratio, 0));
                const where = device.name + " " + scale;
                metrics.font.pixelSize = Math.round(20 * ratio);
                for (const name of names) {
                    metrics.text = name;
                    verify(metrics.advanceWidth <= width, where + " " + name + ": " + metrics.advanceWidth + " > " + width);
                }
                verify(width >= 86 * ratio, where + ": column narrower than the icon");
            }
        }
    }

    // 720x720 HackberryPi: all 15 pinned apps on one page.
    function test_squareScreen() {
        const ratio = pixelRatio(devices[0], 1.0);
        compare(LauncherGrid.columns(720, ratio, 0), 5);
        compare(LauncherGrid.rows(720, Math.round(86 * ratio)), 3);
    }

    function test_wideScreens() {
        compare(LauncherGrid.columns(720, 0.9, 0), 5);
        compare(LauncherGrid.columns(1280, 1.0, 0), 9);
        compare(LauncherGrid.columns(2560, 1.5, 0), 12);
    }

    function test_forcedColumns() {
        compare(LauncherGrid.columns(720, 1.3, 6), 6);
    }

    function test_everyAppHasAPage() {
        const perPage = LauncherGrid.columns(720, 1.5, 0) * LauncherGrid.rows(1440, 128);
        const pages = LauncherGrid.pageCount(22, perPage);
        verify(pages * perPage >= 22);
        compare(pages, 2);
        compare(LauncherGrid.pageCount(0, perPage), 1);
    }
}
