import QtQuick
import MarathonUI.Theme

Grid {
    id: root

    property int defaultColumns: 12
    property int currentColumns: responsive.columns(defaultColumns)
    property real gutterSize: MSpacing.md

    property MResponsive responsive: MResponsive {
        screenWidth: root.width
    }

    columns: currentColumns
    spacing: gutterSize

    property int xs: 12
    property int sm: 6
    property int md: 4
    property int lg: 3
    property int xl: 2
    property int xxl: 1

    function getColumnSpan() {
        return responsive.value(xs, sm, md, lg, xl, xxl);
    }
}
