import QtQuick
import Keel.Actions 1.0
import "Library.js" as Library

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml MusicActions.qml \
//       --app-id org.marathonos.music --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: tracks, loaded and player.
    property var music
    // Runs after the library has loaded: a call can start the app.
    property var _pending: []

    function whenLoaded(run) {
        if (music.loaded)
            run();
        else
            _pending.push(run);
    }

    function summary(track) {
        return {
            id: track.id,
            title: String(track.title).substring(0, 200),
            artist: String(track.artist).substring(0, 200),
            album: String(track.album).substring(0, 200),
            duration: Math.max(0, Math.round(Number(track.duration) || 0))
        };
    }

    Connections {
        target: root.music
        function onLoadedChanged() {
            if (root.music.loaded)
                root._pending.splice(0).forEach(run => run());
        }
    }

    KeelAction {
        name: "library.search"
        title: qsTr("Search music")
        description: "Search the Marathon Music library for songs whose title, artist or album contains the query; an empty query lists every song. Returns up to `limit` songs in title order, each with its id, title, artist, album and length in seconds."
        readOnly: true
        idempotent: true
        parameters: [
            KeelParam {
                name: "query"
                type: "string"
                required: true
                maxLength: 256
            },
            KeelParam {
                name: "limit"
                type: "integer"
                minimum: 1
                maximum: 50
                defaultValue: 20
            }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 50
            KeelParam {
                name: "id"
                type: "integer"
                minimum: 1
                required: true
            }
            KeelParam {
                name: "title"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "artist"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "album"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "duration"
                type: "integer"
                minimum: 0
                required: true
            }
        }
        onInvoked: (args, call) => root.whenLoaded(() => {
                const tracks = root.music.tracks;
                const found = args.query.trim() === "" ? Library.songs(tracks) : Library.search(tracks, args.query);
                call.reply(found.slice(0, args.limit || 20).map(root.summary));
            })
    }

    KeelAction {
        name: "playback.play"
        title: qsTr("Play music")
        description: "Play music from the Marathon Music library: the song `trackId` (an id from library.search) followed by the rest of the library, or every song whose title, artist or album contains `query`. Give one of the two. Returns the song now playing."
        parameters: [
            KeelParam {
                name: "trackId"
                type: "integer"
                minimum: 1
                description: "A song id from library.search"
            },
            KeelParam {
                name: "query"
                type: "string"
                minLength: 1
                maxLength: 256
                description: "Text in a song's title, artist or album"
            }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam {
                name: "id"
                type: "integer"
                minimum: 1
                required: true
            }
            KeelParam {
                name: "title"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "artist"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "album"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "duration"
                type: "integer"
                minimum: 0
                required: true
            }
        }
        onInvoked: (args, call) => root.whenLoaded(() => {
                const player = root.music.player;
                if (args.trackId !== undefined) {
                    const songs = Library.songs(root.music.tracks);
                    const i = songs.findIndex(t => t.id === args.trackId);
                    if (i < 0) {
                        call.fail("Failed", "no song has id " + args.trackId);
                        return;
                    }
                    player.playTracks(songs, i);
                } else if (args.query !== undefined) {
                    const found = Library.search(root.music.tracks, args.query);
                    if (found.length === 0) {
                        call.fail("Failed", "no song matches “" + args.query + "”");
                        return;
                    }
                    player.playTracks(found, 0);
                } else {
                    call.fail("InvalidArguments", "give trackId or query");
                    return;
                }
                call.reply(root.summary(player.currentTrack));
            })
    }

    KeelAction {
        name: "playback.control"
        title: qsTr("Control playback")
        description: "Pause or resume Marathon Music, or skip to the next or previous song in its queue. Fails with NotAvailable when no song is loaded. Returns whether music is playing and the current song's title."
        parameters: [
            KeelParam {
                name: "command"
                type: "string"
                required: true
                values: ["pause", "resume", "next", "previous"]
            }
        ]
        returns: KeelResult {
            type: "object"
            KeelParam {
                name: "playing"
                type: "boolean"
                required: true
            }
            KeelParam {
                name: "title"
                type: "string"
                maxLength: 200
                required: true
            }
        }
        onInvoked: (args, call) => {
            const player = root.music.player;
            if (!player.currentTrack) {
                call.fail("NotAvailable", "no song is loaded");
                return;
            }
            if (args.command === "next")
                player.next();
            else if (args.command === "previous")
                player.previous();
            else if ((args.command === "pause") === player.playing)
                player.toggle();
            call.reply({
                playing: player.playing,
                title: String(player.currentTrack.title).substring(0, 200)
            });
        }
    }
}
