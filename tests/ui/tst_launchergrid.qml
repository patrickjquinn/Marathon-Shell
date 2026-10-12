import QtQuick
import QtTest
import "../../shell/qml/core/LauncherGrid.js" as LauncherGrid

TestCase {
    name: "LauncherGrid"

    // 720x1440 at 150 %: the launcher icon is 1.5x its 86 px base.
    function test_capacityAtLargeScale() {
        const icon = 86 * 1.5;
        compare(LauncherGrid.columns(720, icon, 0), 3);
        compare(LauncherGrid.rows(1440, icon), 3);
    }

    function test_forcedColumns() {
        compare(LauncherGrid.columns(720, 86, 6), 6);
    }

    function test_everyAppHasAPage() {
        const perPage = LauncherGrid.columns(720, 129, 0) * LauncherGrid.rows(1440, 129);
        const pages = LauncherGrid.pageCount(22, perPage);
        verify(pages * perPage >= 22);
        compare(pages, 3);
        compare(LauncherGrid.pageCount(0, perPage), 1);
    }
}
