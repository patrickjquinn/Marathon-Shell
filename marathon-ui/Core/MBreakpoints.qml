pragma Singleton
import QtQuick

QtObject {
    readonly property int xs: 320
    readonly property int sm: 576
    readonly property int md: 768
    readonly property int lg: 1024
    readonly property int xl: 1280
    readonly property int xxl: 1536

    function getBreakpoint(width) {
        if (width >= xxl)
            return "xxl";
        if (width >= xl)
            return "xl";
        if (width >= lg)
            return "lg";
        if (width >= md)
            return "md";
        if (width >= sm)
            return "sm";
        return "xs";
    }

    function isXS(width) {
        return width < sm;
    }
    function isSM(width) {
        return width >= sm && width < md;
    }
    function isMD(width) {
        return width >= md && width < lg;
    }
    function isLG(width) {
        return width >= lg && width < xl;
    }
    function isXL(width) {
        return width >= xl && width < xxl;
    }
    function isXXL(width) {
        return width >= xxl;
    }

    function atLeastSM(width) {
        return width >= sm;
    }
    function atLeastMD(width) {
        return width >= md;
    }
    function atLeastLG(width) {
        return width >= lg;
    }
    function atLeastXL(width) {
        return width >= xl;
    }
    function atLeastXXL(width) {
        return width >= xxl;
    }
}
