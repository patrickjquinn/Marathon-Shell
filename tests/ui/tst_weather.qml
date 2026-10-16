import QtQuick
import QtTest
import "../../shell/qml/core/Weather.js" as Weather

TestCase {
    name: "Weather"

    // 2026-10-16 12:00 UTC
    readonly property int noon: 1760616000

    function hours(precipitation) {
        return precipitation.map((p, i) => ({ time: noon + i * 3600, symbol: p > 0 ? "lightrain" : "cloudy", precipitation: p }));
    }

    function test_conditionNamesMetSymbols() {
        compare(Weather.condition("clearsky"), "Clear");
        compare(Weather.condition("partlycloudy"), "Partly cloudy");
        compare(Weather.condition("lightrainshowers"), "Light rain showers");
        compare(Weather.condition("heavysnow"), "Heavy snow");
        compare(Weather.condition("rainandthunder"), "Rain and thunder");
        compare(Weather.condition("lightssleetshowersandthunder"), "Light sleet showers and thunder");
        compare(Weather.condition("nonsense"), "");
    }

    function test_glyphFollowsDayAndNight() {
        compare(Weather.glyph("clearsky", true), "sun");
        compare(Weather.glyph("clearsky", false), "moon");
        compare(Weather.glyph("fair", false), "cloud-moon");
        compare(Weather.glyph("heavyrainshowers", true), "cloud-rain");
        compare(Weather.glyph("lightssnowshowersandthunder", true), "cloud-lightning");
        compare(Weather.glyph("sleet", true), "cloud-snow");
        compare(Weather.glyph("", true), "cloud");
    }

    function test_units() {
        compare(Weather.temperature(2.4, false), "2°");
        compare(Weather.temperature(-0.4, false), "0°");
        compare(Weather.temperature(0, true), "32°");
        compare(Weather.temperature(null, false), "–");
        compare(Weather.speed(4, false), "14 km/h");
        compare(Weather.speed(4, true), "9 mph");
        compare(Weather.compass(225), "SW");
        compare(Weather.compass(359), "N");
        compare(Weather.uvLevel(6.5), "High");
    }

    function test_clockIsTheLocationsClock() {
        compare(Weather.clock(noon, 3 * 3600, false), "15:00");
        compare(Weather.clock(noon, -5 * 3600, true), "7:00 AM");
        compare(Weather.hour(noon, 0, true), "12 PM");
        compare(Weather.hour(noon + 12 * 3600, 0, false), "00");
    }

    function test_weekday() {
        compare(Weather.weekday("2026-10-17", ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]), "Sat");
    }

    function test_upcomingSkipsThePast() {
        const h = hours([0, 0, 0, 0, 0, 0, 0]);
        compare(Weather.upcoming(h, noon + 2 * 3600 + 60, 2, 3).map(x => x.time), [noon + 2 * 3600, noon + 5 * 3600]);
    }

    function test_outlook() {
        compare(Weather.outlook(hours([0, 0, 0]), noon, 0, false), "Dry for the next 24 hours");
        compare(Weather.outlook(hours([0, 0, 0.5, 1, 2]), noon, 0, false), "Rain from 14:00, about 4 mm");
        compare(Weather.outlook(hours([0.3, 0.2, 0, 0]), noon, 0, false), "Rain stopping around 14:00");
        compare(Weather.outlook([], noon, 0, false), "");
    }

    function test_spanOnTheWeeksScale() {
        const days = [{ low: -2, high: 4 }, { low: 0, high: 8 }];
        compare(Weather.span(days[0], days), { from: 0, to: 0.6 });
        compare(Weather.span(days[1], days), { from: 0.2, to: 1 });
    }
}
