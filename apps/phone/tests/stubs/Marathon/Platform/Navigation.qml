pragma Singleton
import QtQml

QtObject {
    property var launches: []

    function reset() {
        launches = [];
    }
    function launchAppWithRoute(appId, route, params) {
        launches = launches.concat([
            {
                appId: appId,
                route: route,
                params: params
            }
        ]);
        return true;
    }
}
