import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "Search"
    when: windowShown

    Window {
        id: win

        width: 360
        height: 720
        visible: true

        MarathonSearch {
            id: search
            anchors.fill: parent
            active: true
        }
    }

    SignalSpy {
        id: selected
        target: search
        signalName: "resultSelected"
    }

    SignalSpy {
        id: closedSpy
        target: search
        signalName: "closed"
    }

    function result(type, title, appName) {
        return {
            type: type,
            title: title,
            subtitle: "",
            icon: "",
            keywords: [title.toLowerCase()],
            data: {
                appName: appName
            }
        };
    }

    function findAll(item, name, out) {
        for (const child of item.children) {
            if (child.objectName === name)
                out.push(child);
            findAll(child, name, out);
        }
        return out;
    }

    function find(name) {
        return findAll(search, name, [])[0];
    }

    function sectionLabels() {
        return findAll(search, "resultSection", []).filter(h => h.visible).sort((a, b) => a.mapToItem(search, 0, 0).y - b.mapToItem(search, 0, 0).y).map(h => h.text);
    }

    function init() {
        PilotClient.available = true;
        PilotClient.asked = [];
        PilotClient.sheetsShown = 0;
        UnifiedSearchService.results = [];
        search.close();
        selected.clear();
        win.requestActivate();
        tryVerify(() => win.active);
        waitForRendering(search);
    }

    function test_pilotSectionNeedsAQueryAndPilot() {
        verify(!find("pilotSection").visible);
        search.appendToSearch("weather");
        verify(find("pilotSection").visible);
        compare(find("pilotText").text, "Ask “weather”");
        verify(!find("pilotBusy").visible);
        PilotClient.available = false;
        verify(!find("pilotSection").visible);
    }

    function test_enterAsksPilotThenShowsTheAnswer() {
        const question = "how do I share my connection";
        search.appendToSearch(question);
        keyClick(Qt.Key_Return);
        compare(PilotClient.asked, [question]);
        verify(find("pilotBusy").visible);
        verify(find("pilotBusy").running);
        compare(find("pilotText").text, "“" + question + "”");

        PilotClient.answered("something else", "Not this one");
        verify(find("pilotBusy").visible);

        const answer = "Turn on Hotspot: other devices can then join the network it makes.";
        PilotClient.answered(question, answer);
        verify(!find("pilotBusy").visible);
        compare(find("pilotText").text, answer);

        mouseClick(find("pilotBody"));
        compare(PilotClient.sheetsShown, 1);
    }

    function test_anAppPilotOpensIsShown() {
        UIStore.appWindowOpen = false;
        UIStore.currentAppId = "";
        const question = "open mobile network settings";
        search.appendToSearch(question);
        keyClick(Qt.Key_Return);
        compare(PilotClient.asked, [question]);
        closedSpy.clear();
        UIStore.currentAppId = "settings";
        UIStore.appWindowOpen = true;
        PilotClient.answered(question, "Settings is open at mobile network.");
        compare(closedSpy.count > 0, true);
        UIStore.appWindowOpen = false;
        UIStore.currentAppId = "";
    }

    function test_anAnswerWithoutAnAppStays() {
        UIStore.appWindowOpen = false;
        UIStore.currentAppId = "";
        const question = "how far is the moon";
        search.appendToSearch(question);
        keyClick(Qt.Key_Return);
        closedSpy.clear();
        PilotClient.answered(question, "About 384,400 km.");
        compare(closedSpy.count, 0);
        compare(find("pilotText").text, "About 384,400 km.");
    }

    function test_enterOpensTheResultTheQueryNames() {
        UnifiedSearchService.results = [result("app", "Settings", "")];
        search.appendToSearch("sett");
        keyClick(Qt.Key_Return);
        tryCompare(selected, "count", 1);
        compare(selected.signalArguments[0][0].title, "Settings");
        compare(PilotClient.asked, []);
    }

    function test_resultsFollowUnderSectionLabels() {
        UnifiedSearchService.results = [result("deeplink", "Hotspot", "Settings"), result("app", "Settings", ""), result("deeplink", "Mobile network", "Settings")];
        search.appendToSearch("hot");
        compare(search.searchResults.map(r => r.title), ["Hotspot", "Mobile network", "Settings"]);
        tryVerify(() => sectionLabels().length === 2);
        compare(sectionLabels(), ["Settings", "Apps"]);
    }
}
