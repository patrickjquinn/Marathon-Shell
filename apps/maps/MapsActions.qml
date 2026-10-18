import QtQuick
import Keel.Actions 1.0
import "MapsLogic.js" as Logic

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml MapsActions.qml \
//       --app-id org.marathonos.maps --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: fetch, fix, selectPlace(), requestDirections() and activate().
    property var app

    function place(args) {
        const name = String(args.name || "").trim() || args.lat.toFixed(5) + ", " + args.lon.toFixed(5);
        return { name: name, address: name, lat: args.lat, lon: args.lon, type: "" };
    }

    function summary(place) {
        return {
            name: place.name.substring(0, 256),
            address: place.address.substring(0, 1024),
            lat: place.lat,
            lon: place.lon,
            type: place.type.substring(0, 64)
        };
    }

    KeelAction {
        name: "places.search"
        title: qsTr("Search places")
        description: "Search OpenStreetMap (Nominatim), as Marathon Maps' search does, for places, addresses and businesses matching the query, favouring places near the person when Maps knows where they are. Returns up to `limit` places, each with its name, full address, latitude, longitude and kind."
        readOnly: true
        idempotent: true
        openWorld: true
        parameters: [
            KeelParam { name: "query"; type: "string"; required: true; minLength: 1; maxLength: 256 },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 10; defaultValue: 5 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 10
            KeelParam { name: "name"; type: "string"; maxLength: 256; required: true }
            KeelParam { name: "address"; type: "string"; maxLength: 1024; required: true }
            KeelParam { name: "lat"; type: "number"; minimum: -90; maximum: 90; required: true }
            KeelParam { name: "lon"; type: "number"; minimum: -180; maximum: 180; required: true }
            KeelParam { name: "type"; type: "string"; maxLength: 64; required: true }
        }
        onInvoked: (args, call) => {
            const app = root.app;
            app.fetch(Logic.searchUrl(args.query, app.fixValid ? app.fix : null), (status, text) => {
                const places = status === 200 ? Logic.parseResults(text) : null;
                if (places === null)
                    call.fail("Failed", status === 0 ? "couldn't reach the search service" : "the search service isn't responding");
                else
                    call.reply(places.slice(0, args.limit || 5).map(root.summary));
            });
        }
    }

    KeelAction {
        name: "map.show"
        title: qsTr("Show on map")
        description: "Show a place to the person in Marathon Maps: brings Maps to the front with the map centred on the latitude and longitude and a pin there, named `name` (for example a place from places.search). The place is added to Maps' recent places."
        idempotent: true
        parameters: [
            KeelParam { name: "lat"; type: "number"; required: true; minimum: -90; maximum: 90 },
            KeelParam { name: "lon"; type: "number"; required: true; minimum: -180; maximum: 180 },
            KeelParam { name: "name"; type: "string"; maxLength: 256; description: "What the place is called" }
        ]
        onInvoked: (args, call) => {
            root.app.selectPlace(root.place(args));
            root.app._toMap();
            root.app.activate();
        }
    }

    KeelAction {
        name: "directions.show"
        title: qsTr("Show directions")
        description: "Plan a route in Marathon Maps from the person's location to the latitude and longitude, by car, on foot or by bicycle, and bring Maps to the front showing it; the person starts turn-by-turn navigation from there. Without a location fix Maps asks the person to tap a starting point."
        idempotent: true
        parameters: [
            KeelParam { name: "lat"; type: "number"; required: true; minimum: -90; maximum: 90 },
            KeelParam { name: "lon"; type: "number"; required: true; minimum: -180; maximum: 180 },
            KeelParam { name: "name"; type: "string"; maxLength: 256; description: "What the destination is called" },
            KeelParam { name: "mode"; type: "string"; values: ["auto", "pedestrian", "bicycle"]; defaultValue: "auto"; description: "auto drives, pedestrian walks, bicycle cycles" }
        ]
        onInvoked: (args, call) => {
            const app = root.app;
            app.currentMode = args.mode || "auto";
            app.selectPlace(root.place(args));
            app.requestDirections();
            app.activate();
        }
    }
}
