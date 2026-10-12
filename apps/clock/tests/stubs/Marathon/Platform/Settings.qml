pragma Singleton
import QtQml

QtObject {
    property var values: ({})

    function get(key, defaultValue) {
        return key in values ? values[key] : defaultValue;
    }

    function set(key, value) {
        const next = Object.assign({}, values);
        next[key] = value;
        values = next;
    }
}
