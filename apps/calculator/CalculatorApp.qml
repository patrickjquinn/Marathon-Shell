pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app
    appId: "calculator"

    property Calculator calc: Calculator {}

    cover: Component {
        CalculatorCover {
            calc: app.calc
        }
    }

    initialPage: Component {
        CalculatorPage {
            calc: app.calc
        }
    }
}
