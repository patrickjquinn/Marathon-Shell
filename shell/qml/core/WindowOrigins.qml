pragma Singleton
import QtQuick

// Where an app window comes from and goes to: the icon or switcher card a
// launch grows out of, and the card a minimise lands on.
QtObject {
    id: root

    property rect launchRect: Qt.rect(0, 0, 0, 0)
    property bool launchFromCard: false
    property real launchTime: 0
    // MarathonTaskSwitcher; answers cardRect(appId) and revealCard(appId).
    property var switcher: null
    readonly property real cardRadius: switcher ? switcher.coverRadius : 0
    // The app whose card the flying window stands in for; its card hides its cover.
    property string dockingAppId: ""

    function markLaunch(item, fromCard) {
        launchRect = item.mapToItem(null, 0, 0, item.width, item.height);
        launchFromCard = fromCard === true;
        launchTime = Date.now();
    }

    // The origin of the launch now being shown, once; null when there is none.
    function takeLaunch() {
        if (launchTime === 0 || Date.now() - launchTime > 1500)
            return null;
        launchTime = 0;
        return {
            "rect": launchRect,
            "fromCard": launchFromCard
        };
    }

    // Scene rect of the app's switcher cover; empty when it has no card.
    function cardRect(appId) {
        return switcher ? switcher.cardRect(appId) : Qt.rect(0, 0, 0, 0);
    }

    function revealCard(appId) {
        if (switcher)
            switcher.revealCard(appId);
    }
}
