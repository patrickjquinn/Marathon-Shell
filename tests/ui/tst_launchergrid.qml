import QtQuick
import QtTest
import "../../shell/qml/core/LauncherGrid.js" as LauncherGrid

TestCase {
    name: "LauncherGrid"

    // 720x1440 at 150 %: the launcher icon is 1.5x its 86 px base.
    function test_capacityAtLargeScale() {
        const icon = 86 * 1.5;
        compare(LauncherGrid.columns(720, icon, 0), 4);
        compare(LauncherGrid.rows(1440, icon), 4);
    }

    // 720 px wide phones at their default pixel ratios: PinePhone 1.20,
    // Librem 5 1.30, QEMU 1.35.
    function test_tallPhones() {
        for (const ratio of [1.2, 1.3, 1.35])
            compare(LauncherGrid.columns(720, Math.round(86 * ratio), 0), 5, "ratio " + ratio);
    }

    // 720x720 HackberryPi at ratio 1.15: all 15 pinned apps on one page.
    function test_squareScreen() {
        const icon = Math.round(86 * 1.15);
        compare(LauncherGrid.columns(720, icon, 0), 5);
        compare(LauncherGrid.rows(720, icon), 3);
    }

    function test_forcedColumns() {
        compare(LauncherGrid.columns(720, 86, 6), 6);
    }

    function test_everyAppHasAPage() {
        const perPage = LauncherGrid.columns(720, 129, 0) * LauncherGrid.rows(1440, 129);
        const pages = LauncherGrid.pageCount(22, perPage);
        verify(pages * perPage >= 22);
        compare(pages, 2);
        compare(LauncherGrid.pageCount(0, perPage), 1);
    }
}
