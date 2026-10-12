pragma Singleton
import QtQml
QtObject {
    function get(key, fallback) { return fallback; }
}
