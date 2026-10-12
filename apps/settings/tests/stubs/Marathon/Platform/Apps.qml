pragma Singleton
import QtQml.Models

ListModel {
    function reset() {
        clear();
        append({ id: "settings", name: "Settings", icon: "", version: "1.0.0", isProtected: true });
        append({ id: "notes", name: "Notes", icon: "", version: "1.2.0", isProtected: false });
        append({ id: "weather", name: "Weather", icon: "", version: "0.9.0", isProtected: false });
    }
}
