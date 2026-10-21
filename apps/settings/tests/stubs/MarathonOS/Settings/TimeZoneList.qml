import QtQml

QtObject {
    readonly property var zones: [
        { id: "Europe/Berlin", city: "Berlin", region: "Europe", offset: "UTC+01:00" },
        { id: "Europe/London", city: "London", region: "Europe", offset: "UTC+00:00" },
        { id: "America/New_York", city: "New York", region: "America", offset: "UTC-05:00" }
    ]

    function search(query) {
        const q = String(query).toLowerCase();
        return zones.filter(z => q === "" || (z.city + " " + z.region + " " + z.id).toLowerCase().indexOf(q) >= 0);
    }
    function displayName(id) {
        const zone = zones.find(z => z.id === id);
        return zone ? zone.city + " (" + zone.offset + ")" : id;
    }
}
