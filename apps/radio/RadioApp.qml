pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "cover"
import "pages"

// Radio: the world's stations on a globe, and the phone's own FM tuner.
// marathon-radiod does the work (tuning, streaming, metadata, MPRIS); the
// app shows it and asks.
ApplicationWindow {
    id: app

    readonly property alias radio: service

    appId: "radio"

    RadioService {
        id: service
    }

    RadioActions {
        radio: service
    }

    cover: Component {
        RadioCover {
            radio: service
        }
    }

    initialPage: Component {
        GlobePage {
            app: app
        }
    }
}
