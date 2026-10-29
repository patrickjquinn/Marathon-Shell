pragma Singleton
import QtQml

QtObject {
    property var forecast: ({})
    property string state: ""
    property bool fahrenheit: false
    property bool milesPerHour: false
    property var calls: []

    signal searchFinished(var places, string error)

    function refresh() {
        calls.push("refresh");
    }
    function search(q) {
        calls.push("search:" + q);
    }
    function setLocation(p) {
        calls.push("setLocation:" + p.name);
    }
    function setAutomatic() {
        calls.push("setAutomatic");
    }

    // A day of showers in Tampere, from the current hour on.
    function sample() {
        const now = Math.floor(Date.now() / 3600000) * 3600;
        const hourly = [];
        for (let i = 0; i < 48; ++i) {
            const h = (new Date((now + i * 3600) * 1000)).getUTCHours();
            const wet = i >= 4 && i <= 8;
            hourly.push({
                time: now + i * 3600,
                temperature: 2 + 3 * Math.sin((h - 9) / 24 * 2 * Math.PI),
                symbol: wet ? "lightrainshowers" : i < 4 ? "partlycloudy" : "cloudy",
                precipitation: wet ? 0.4 + (i - 4) * 0.3 : 0,
                precipitation_probability: wet ? 60 : 10,
                wind_speed: 4,
                wind_direction: 225,
                is_day: h >= 7 && h < 18
            });
        }
        const daily = [];
        const symbols = ["rainshowers", "cloudy", "partlycloudy", "clearsky", "lightsnow", "heavyrain", "fair", "cloudy", "sleet", "rainandthunder"];
        for (let d = 0; d < 10; ++d) {
            const date = new Date((now + d * 86400) * 1000);
            daily.push({
                date: date.toISOString().slice(0, 10),
                high: 4 + (d % 4) * 2,
                low: -3 + (d % 3),
                symbol: symbols[d],
                precipitation: d === 0 ? 4.1 : 0.5 * d,
                precipitation_probability: [60, 10, 0, 0, 40, 90, 0, 20, 70, 80][d],
                wind_speed_max: 6,
                uv_max: 1.2,
                sunrise: now - 4 * 3600,
                sunset: now + 5 * 3600
            });
        }
        return {
            location: {
                name: "Tampere",
                region: "Pirkanmaa, Finland",
                latitude: 61.4981,
                longitude: 23.7608,
                automatic: true
            },
            updated: now,
            attribution: "MET Norway",
            timezone_offset: 0,
            current: {
                time: now,
                temperature: 2.1,
                apparent: -1.4,
                symbol: "partlycloudy",
                wind_speed: 4,
                wind_gust: 7.2,
                wind_direction: 225,
                humidity: 87,
                pressure: 1009.3,
                uv_index: 0.4,
                cloud_cover: 60,
                precipitation_1h: 0,
                precipitation_probability: 10,
                dew_point: 0.1
            },
            hourly: hourly,
            daily: daily
        };
    }
}
