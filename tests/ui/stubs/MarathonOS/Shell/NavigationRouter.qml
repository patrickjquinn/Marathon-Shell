pragma Singleton
import QtQml
QtObject {
    property var deepLinks: []
    function navigateToDeepLink(appId, route, params) {
        deepLinks = deepLinks.concat([{ appId: appId, params: params }]);
        return true;
    }
}
