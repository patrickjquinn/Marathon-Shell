pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "pages"

ApplicationWindow {
    id: app
    appId: "calculator"

    property Calculator calc: Calculator {}

    initialPage: Component {
        CalculatorPage {
            calc: app.calc
        }
    }
}
