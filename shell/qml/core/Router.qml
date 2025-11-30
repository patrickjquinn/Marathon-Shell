pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: router

    property int currentPageIndex: 2
    property int previousPageIndex: 2

    readonly property int pageHub: 0
    readonly property int pageFrames: 1
    readonly property int pageApps: 2

    signal navigateToHub
    signal navigateToFrames
    signal navigateToApps(int appPage)
    signal navigateBack
    signal navigateNext
    signal navigateToSettingPage(string settingId)

    function goToHub() {
        Logger.nav("current", "Hub", "direct");
        previousPageIndex = currentPageIndex;
        currentPageIndex = pageHub;
        navigateToHub();
    }

    function goToFrames() {
        Logger.nav("current", "ActiveFrames", "direct");
        previousPageIndex = currentPageIndex;
        currentPageIndex = pageFrames;
        navigateToFrames();
    }

    function goToAppPage(page) {
        Logger.nav("current", "AppPage" + page, "direct");
        previousPageIndex = currentPageIndex;
        currentPageIndex = pageApps + page;
        navigateToApps(page);
    }

    function goBack() {
        Logger.nav("current", "previous", "back");
        var temp = currentPageIndex;
        currentPageIndex = previousPageIndex;
        previousPageIndex = temp;
        navigateBack();
    }

    function navigateLeft() {
        if (currentPageIndex < 10) {
            previousPageIndex = currentPageIndex;
            currentPageIndex++;
            Logger.nav("page" + previousPageIndex, "page" + currentPageIndex, "swipeLeft");
        }
    }

    function navigateRight() {
        if (currentPageIndex > 0) {
            previousPageIndex = currentPageIndex;
            currentPageIndex--;
            Logger.nav("page" + previousPageIndex, "page" + currentPageIndex, "swipeRight");
        }
    }

    function getCurrentPage() {
        return currentPageIndex - 2;
    }

    function navigateToSetting(settingId) {
        Logger.nav("current", "Setting:" + settingId, "search");
        navigateToSettingPage(settingId);
    }
}
