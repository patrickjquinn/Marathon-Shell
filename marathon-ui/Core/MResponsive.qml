import QtQuick

// Responsive breakpoint helper. Mirrors MBreakpoints constants inline
// because qmllint can't resolve composite-singleton properties when
// linting source files outside the staged module dir — see the qmllint
// sweep notes in commit history.
QtObject {
    readonly property int _sm: 576
    readonly property int _md: 768
    readonly property int _lg: 1024
    readonly property int _xl: 1280
    readonly property int _xxl: 1536

    property int screenWidth: 800
    property int screenHeight: 600

    readonly property bool isXS: screenWidth < _sm
    readonly property bool isSM: screenWidth >= _sm && screenWidth < _md
    readonly property bool isMD: screenWidth >= _md && screenWidth < _lg
    readonly property bool isLG: screenWidth >= _lg && screenWidth < _xl
    readonly property bool isXL: screenWidth >= _xl && screenWidth < _xxl
    readonly property bool isXXL: screenWidth >= _xxl

    readonly property string currentBreakpoint: isXXL ? "xxl" : isXL ? "xl" : isLG ? "lg" : isMD ? "md" : isSM ? "sm" : "xs"

    readonly property bool isMobile: isXS || isSM
    readonly property bool isTablet: isMD
    readonly property bool isDesktop: isLG || isXL || isXXL

    readonly property bool atLeastSM: screenWidth >= _sm
    readonly property bool atLeastMD: screenWidth >= _md
    readonly property bool atLeastLG: screenWidth >= _lg
    readonly property bool atLeastXL: screenWidth >= _xl
    readonly property bool atLeastXXL: screenWidth >= _xxl

    function value(xsValue, smValue, mdValue, lgValue, xlValue, xxlValue) {
        if (isXXL && xxlValue !== undefined)
            return xxlValue;
        if (isXL && xlValue !== undefined)
            return xlValue;
        if (isLG && lgValue !== undefined)
            return lgValue;
        if (isMD && mdValue !== undefined)
            return mdValue;
        if (isSM && smValue !== undefined)
            return smValue;
        return xsValue;
    }

    function columns(defaultCols) {
        if (isXS)
            return Math.max(1, Math.floor(defaultCols / 4));
        if (isSM)
            return Math.max(1, Math.floor(defaultCols / 2));
        if (isMD)
            return Math.max(1, Math.floor(defaultCols * 0.75));
        return defaultCols;
    }
}
