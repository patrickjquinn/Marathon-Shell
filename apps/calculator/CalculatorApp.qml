pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Configuration 1.0
import "pages"
import "cover"

ApplicationWindow {
    id: app
    appId: "calculator"

    property QtObject modeStore: ConfigurationValue {
        key: "/apps/calculator/scientific"
        defaultValue: true
    }
    property QtObject historyStore: ConfigurationValue {
        key: "/apps/calculator/history"
        defaultValue: "[]"
    }
    property bool _restored: false
    property Calculator calc: Calculator {
        onHistoryChanged: {
            if (app._restored)
                app.historyStore.value = JSON.stringify(history);
        }
    }

    Component.onCompleted: {
        try {
            const saved = JSON.parse(historyStore.value);
            if (Array.isArray(saved))
                calc.history = saved;
        } catch (e) {
            historyStore.value = "[]";
        }
        _restored = true;
    }

    CalculatorActions {
        calc: app.calc
    }

    cover: Component {
        CalculatorCover {
            calc: app.calc
        }
    }

    initialPage: Component {
        CalculatorPage {
            calc: app.calc
            scientific: app.modeStore.value
            onScientificChanged: app.modeStore.value = scientific
        }
    }
}
