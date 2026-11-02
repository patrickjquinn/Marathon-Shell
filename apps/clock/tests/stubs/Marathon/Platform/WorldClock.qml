pragma Singleton
import QtQml

QtObject {
    function utcOffset(tz) {
        return tz === "Asia/Tokyo" ? 9 * 3600 : tz === "Nowhere/Gone" ? undefined : 0;
    }
    function localZone() {
        return "Europe/Dublin";
    }
}
