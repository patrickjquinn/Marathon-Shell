import QtQuick
import Keel.Actions 1.0
import "GalleryModel.js" as Model

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml GalleryActions.qml \
//       --app-id org.marathonos.gallery --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: photos, refresh(), pageStack and activate().
    property var store

    // A call can start the app before its first refresh.
    function photos() {
        if (store.photos.length === 0)
            store.refresh();
        return store.photos;
    }

    function summary(photo) {
        return {
            id: photo.id,
            name: Model.fileName(photo).substring(0, 256),
            album: String(photo.album || "").substring(0, 256),
            taken: new Date(Number(photo.timestamp) || 0).toISOString(),
            width: Math.max(0, photo.width || 0),
            height: Math.max(0, photo.height || 0)
        };
    }

    KeelAction {
        name: "photos.find"
        title: qsTr("Find photos")
        description: "Find photos in Marathon Gallery whose file name, album or date (as \"12 March 2026\") contains the query; an empty query lists the most recent. Returns up to `limit` photos, newest first, each with its id, file name, album, when it was taken and its size in pixels."
        readOnly: true
        idempotent: true
        parameters: [
            KeelParam { name: "query"; type: "string"; required: true; maxLength: 256 },
            KeelParam { name: "limit"; type: "integer"; minimum: 1; maximum: 50; defaultValue: 10 }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 50
            KeelParam { name: "id"; type: "integer"; minimum: 1; required: true }
            KeelParam { name: "name"; type: "string"; maxLength: 256; required: true }
            KeelParam { name: "album"; type: "string"; maxLength: 256; required: true }
            KeelParam { name: "taken"; type: "string"; format: "date-time"; maxLength: 32; required: true }
            KeelParam { name: "width"; type: "integer"; minimum: 0; required: true }
            KeelParam { name: "height"; type: "integer"; minimum: 0; required: true }
        }
        onInvoked: (args, call) => {
            const found = Model.filter(root.photos(), args.query);
            call.reply(found.slice(0, args.limit || 10).map(root.summary));
        }
    }

    KeelAction {
        name: "photos.show"
        title: qsTr("Show photo")
        description: "Open a photo full screen in Marathon Gallery for the person, by its id from photos.find, and bring Gallery to the front. Swiping moves through the other photos, newest first."
        parameters: [
            KeelParam { name: "id"; type: "integer"; minimum: 1; required: true; description: "A photo id from photos.find" }
        ]
        onInvoked: (args, call) => {
            const photos = root.photos();
            const index = photos.findIndex(p => p.id === args.id);
            if (index < 0) {
                call.fail("Failed", "no photo has id " + args.id);
                return;
            }
            root.store.pageStack.push(Qt.resolvedUrl("pages/PhotoViewerPage.qml"),
                                      { store: root.store, photos: photos, currentIndex: index });
            root.store.activate();
        }
    }
}
