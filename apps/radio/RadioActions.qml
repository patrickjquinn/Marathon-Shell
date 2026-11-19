import QtQuick
import Keel.Actions 1.0

// What Pilot and other assistants can ask of Radio. keel-actions.json is
// generated from these declarations; after changing one, run (in crates/)
//   cargo run -q -p keel-actions-codegen --bin keel-actions -- \
//       --qml ../apps/radio/RadioActions.qml --app-id org.marathonos.radio \
//       --out ../apps/radio/keel-actions.json
Item {
    id: root

    property var radio

    function summary(s) {
        return {
            "id": String(s.id),
            "name": String(s.name).substring(0, 200),
            "country": String(s.country || "").substring(0, 100),
            "fm": s.fm > 0 ? Math.round(s.fm / 100) / 10 : 0
        };
    }

    KeelAction {
        name: "radio.search"
        title: qsTr("Find radio stations")
        description: "Find radio stations by name, genre or city, from the phone's FM band and the world's internet radio; stations on FM here come first. Returns up to `limit` stations, each with its id, name, country and FM frequency in MHz (0 when it is internet-only)."
        readOnly: true
        idempotent: true
        onInvoked: (args, call) => {
            return root.radio.search(args.query, list => {
                return call.reply(list.slice(0, args.limit || 10).map(root.summary));
            });
        }
        parameters: [
            KeelParam {
                name: "query"
                type: "string"
                required: true
                minLength: 2
                maxLength: 200
            },
            KeelParam {
                name: "limit"
                type: "integer"
                minimum: 1
                maximum: 30
                defaultValue: 10
            }
        ]

        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 30

            KeelParam {
                name: "id"
                type: "string"
                maxLength: 100
                required: true
            }

            KeelParam {
                name: "name"
                type: "string"
                maxLength: 200
                required: true
            }

            KeelParam {
                name: "country"
                type: "string"
                maxLength: 100
                required: true
            }

            KeelParam {
                name: "fm"
                type: "number"
                minimum: 0
                required: true
            }
        }
    }

    KeelAction {
        name: "radio.play"
        title: qsTr("Play the radio")
        description: "Play a radio station: the station `id` from radio.search, else the best match for `query` (a station's name, a genre or a city; one on FM here comes first), else the station played last. Returns the station now playing."
        onInvoked: (args, call) => {
            const wanted = args.id || args.query;
            if (!wanted) {
                const last = root.radio.station;
                if (!last) {
                    call.fail("NotAvailable", "no station has been played yet; give a query");
                    return;
                }
                root.radio.toggle();
                call.reply(root.summary(last));
                return;
            }
            root.radio.search(wanted, list => {
                const found = args.id ? list.filter(s => {
                    return s.id === args.id;
                }) : list;
                if (found.length === 0) {
                    call.fail("Failed", "no station matches “" + wanted + "”");
                    return;
                }
                root.radio.play(found[0], list);
                call.reply(root.summary(found[0]));
            });
        }
        parameters: [
            KeelParam {
                name: "id"
                type: "string"
                maxLength: 100
                description: "A station id from radio.search"
            },
            KeelParam {
                name: "query"
                type: "string"
                minLength: 2
                maxLength: 200
                description: "A station's name, a genre or a city"
            }
        ]

        returns: KeelResult {
            type: "object"

            KeelParam {
                name: "id"
                type: "string"
                maxLength: 100
                required: true
            }

            KeelParam {
                name: "name"
                type: "string"
                maxLength: 200
                required: true
            }

            KeelParam {
                name: "country"
                type: "string"
                maxLength: 100
                required: true
            }

            KeelParam {
                name: "fm"
                type: "number"
                minimum: 0
                required: true
            }
        }
    }

    KeelAction {
        name: "radio.tune"
        title: qsTr("Tune the FM radio")
        description: "Tune the phone's FM radio to `frequency` MHz (87.5 to 108). FM needs wired headphones plugged in: they are the aerial."
        idempotent: true
        onInvoked: (args, call) => {
            if (!root.radio.tuner) {
                call.fail("NotAvailable", "this phone has no FM radio");
                return;
            }
            root.radio.tune(Math.round(args.frequency * 10) * 100);
            call.reply(null);
        }
        parameters: [
            KeelParam {
                name: "frequency"
                type: "number"
                required: true
                minimum: 87.5
                maximum: 108
            }
        ]
    }

    KeelAction {
        name: "radio.stop"
        title: qsTr("Stop the radio")
        description: "Stop the radio, if it is playing."
        idempotent: true
        onInvoked: (args, call) => {
            root.radio.stop();
            call.reply(null);
        }
    }
}
