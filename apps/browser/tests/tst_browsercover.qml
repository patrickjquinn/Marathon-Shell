import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    id: testCase

    name: "BrowserCover"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: coverComponent
        BrowserCover {}
    }
    Component {
        id: appComponent
        TestBrowser {}
    }

    function test_emptyShowsPlaceholder() {
        const cover = createTemporaryObject(coverComponent, testCase);
        verify(findChild(cover, "coverPlaceholder").visible);
        verify(!findChild(cover, "coverThumbnail").visible);
    }

    function test_showsTitleHostAndThumbnail() {
        const cover = createTemporaryObject(coverComponent, testCase, {
            title: "KDE",
            url: "https://www.kde.org/a",
            thumbnail: "image://theme/icon-l-browser"
        });
        verify(!findChild(cover, "coverPlaceholder").visible);
        compare(findChild(cover, "coverTitle").text, "KDE");
        compare(findChild(cover, "coverHost").text, "kde.org");
        verify(findChild(cover, "coverThumbnail").visible);
        verify(!findChild(cover, "coverText").visible);
        cover.thumbnail = "";
        verify(findChild(cover, "coverText").visible);
    }

    function test_newTabAction() {
        const cover = createTemporaryObject(coverComponent, testCase);
        let fired = 0;
        cover.newTabRequested.connect(() => fired++);
        findChild(cover, "newTabAction").triggered();
        compare(fired, 1);
    }

    function test_appCoverFollowsTheCurrentTab() {
        const app = createTemporaryObject(appComponent, testCase);
        tryCompare(app.pageStack, "depth", 1);
        const cover = app.cover.createObject(testCase);
        app.navigateTo("https://kde.org");
        app.tabs.setProperty(0, "title", "KDE");
        compare(cover.title, "KDE");
        compare(cover.url, "https://kde.org");
        cover.newTabRequested();
        compare(app.tabs.count, 2);
        verify(app.editingAddress);
        cover.destroy();
    }
}
