import QtQuick

QtObject {
    property int screenWidth: 800
    property int screenHeight: 600

    readonly property string currentBreakpoint: MBreakpoints.getBreakpoint(screenWidth)

    readonly property bool isXS: MBreakpoints.isXS(screenWidth)
    readonly property bool isSM: MBreakpoints.isSM(screenWidth)
    readonly property bool isMD: MBreakpoints.isMD(screenWidth)
    readonly property bool isLG: MBreakpoints.isLG(screenWidth)
    readonly property bool isXL: MBreakpoints.isXL(screenWidth)
    readonly property bool isXXL: MBreakpoints.isXXL(screenWidth)

    readonly property bool isMobile: isXS || isSM
    readonly property bool isTablet: isMD
    readonly property bool isDesktop: isLG || isXL || isXXL

    readonly property bool atLeastSM: MBreakpoints.atLeastSM(screenWidth)
    readonly property bool atLeastMD: MBreakpoints.atLeastMD(screenWidth)
    readonly property bool atLeastLG: MBreakpoints.atLeastLG(screenWidth)
    readonly property bool atLeastXL: MBreakpoints.atLeastXL(screenWidth)
    readonly property bool atLeastXXL: MBreakpoints.atLeastXXL(screenWidth)

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
