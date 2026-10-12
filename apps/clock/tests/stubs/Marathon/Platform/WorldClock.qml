pragma Singleton
import QtQml

QtObject {
    function timeIn(tz) {
        return { time: "12:00 PM", weekday: "MON", offsetLabel: tz === "Europe/London" ? "Local" : "+1h" };
    }
}
