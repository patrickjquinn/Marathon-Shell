import QtQuick
import QtTest
import "../../shell/qml/core/Clock.js" as Clock

TestCase {
    name: "Clock"

    readonly property date afternoon: new Date(2026, 9, 26, 13, 5)

    function test_twentyFourHourSetting() {
        compare(Clock.format(afternoon, "24h", Qt.locale("en_US")), "13:05");
    }

    function test_twelveHourSetting() {
        // CLDR puts a narrow no-break space before the AM/PM text.
        compare(Clock.format(afternoon, "12h", Qt.locale("en_US")).replace(/\s/g, " "), "1:05 PM");
    }

    function test_germanTwentyFourHour() {
        compare(Clock.format(afternoon, "24h", Qt.locale("de_DE")), "13:05");
    }

    function test_germanTwelveHourUsesLocaleText() {
        verify(/^1:05 (PM|nachm\.)$/.test(Clock.format(afternoon, "12h", Qt.locale("de_DE")).replace(/\s/g, " ")));
    }
}
