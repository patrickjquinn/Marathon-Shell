import QtQuick
import QtQuick.Controls

Item {
    id: router

    property StackView stackView: null
    property var routeMap: ({})
    property string appId: ""
    property bool enableDeepLinks: true
    property bool enableBackHandling: true
    property bool enableNavigationDepth: true
    property var navigationTarget: null
    property var navigationDepthTarget: null
    property var pageRequestedTarget: null
    property var backRequestedTarget: null

    function updateNavigationDepth() {
        if (!enableNavigationDepth || !stackView)
            return;
        var newDepth = stackView.depth - 1;
        if (navigationTarget && navigationTarget.navigationDepth !== undefined)
            navigationTarget.navigationDepth = newDepth;
        if (navigationDepthTarget && navigationDepthTarget.navigationDepth !== undefined)
            navigationDepthTarget.navigationDepth = newDepth;
    }

    function resolveRoute(route, params) {
        if (!routeMap)
            return null;
        var entry = routeMap[route];
        if (!entry)
            return null;
        if (typeof entry === "function")
            return entry(params || {});
        return entry;
    }

    function pushRoute(route, params) {
        if (!stackView)
            return false;
        var component = resolveRoute(route, params);
        if (!component)
            return false;
        stackView.push(component, params || {});
        return true;
    }

    function popRoute() {
        if (!stackView)
            return false;
        if (stackView.depth > 1) {
            stackView.pop();
            return true;
        }
        return false;
    }

    function handleBackPress() {
        if (enableBackHandling)
            popRoute();
    }

    Component.onCompleted: updateNavigationDepth()

    Connections {
        target: stackView

        function onDepthChanged() {
            router.updateNavigationDepth();
        }
    }

    Connections {
        target: navigationTarget

        function onBackPressed() {
            router.handleBackPress();
        }
    }

    Connections {
        target: pageRequestedTarget

        function onPageRequested(pageName, params) {
            router.pushRoute(pageName, params);
        }
    }

    Connections {
        target: backRequestedTarget ? backRequestedTarget : pageRequestedTarget

        function onBackRequested() {
            router.popRoute();
        }
    }

    Connections {
        target: enableDeepLinks && typeof NavigationRouter !== "undefined" && NavigationRouter ? NavigationRouter : null

        function onDeepLinkRequested(appId, route, params) {
            if (router.appId === "" || appId === router.appId)
                router.pushRoute(route, params);
        }

        function onSettingsNavigationRequested(page, subpage, params) {
            if (router.appId === "" || router.appId === "settings")
                router.pushRoute(page, params);
        }
    }
}
