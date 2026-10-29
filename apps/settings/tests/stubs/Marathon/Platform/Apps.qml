pragma Singleton
import QtQml.Models

ListModel {
    function reset() {
        clear();
        append({
            id: "settings",
            name: "Settings",
            icon: "",
            version: "1.0.0",
            isProtected: true
        });
        append({
            id: "notes",
            name: "Notes",
            icon: "",
            version: "1.2.0",
            isProtected: false
        });
        append({
            id: "weather",
            name: "Weather",
            icon: "",
            version: "0.9.0",
            isProtected: false
        });
    }
    function getAllAppIds() {
        const ids = [];
        for (let i = 0; i < count; i++)
            ids.push(get(i).id);
        return ids;
    }
    // The real registry's getApp also carries the manifest's permissions.
    function getApp(appId) {
        const perms = {
            settings: ["system", "network", "storage"],
            notes: ["storage"],
            weather: ["network", "location", "system"]
        };
        for (let i = 0; i < count; i++) {
            if (get(i).id === appId)
                return Object.assign({}, get(i), {
                    permissions: perms[appId] || []
                });
        }
        return {};
    }
}
