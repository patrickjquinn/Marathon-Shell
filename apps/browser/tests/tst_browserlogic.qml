import QtQuick
import QtTest
import "../BrowserLogic.js" as Logic

TestCase {
    name: "BrowserLogic"

    function test_parseList() {
        compare(Logic.parseList(""), []);
        compare(Logic.parseList("{bad"), []);
        compare(Logic.parseList("{\"a\":1}"), []);
        compare(Logic.parseList("[1]"), [1]);
    }

    function test_schemeBadge() {
        compare(Logic.schemeBadge("https://a.org"), "secure");
        compare(Logic.schemeBadge("HTTP://a.org"), "insecure");
        compare(Logic.schemeBadge("about:blank"), "none");
        compare(Logic.schemeBadge(undefined), "none");
    }

    function test_displayHost() {
        compare(Logic.displayHost("https://www.duckduckgo.com/?q=x"), "duckduckgo.com");
        compare(Logic.displayHost("http://192.168.1.5:8080/a"), "192.168.1.5:8080");
        compare(Logic.displayHost("https://user:pw@example.com/"), "example.com");
        compare(Logic.displayHost("https://evil.com?x=@paypal.com"), "evil.com");
        compare(Logic.displayHost("about:blank"), "about:blank");
    }

    function test_resolveInput() {
        const engine = "https://s.example/?q=";
        compare(Logic.resolveInput("en.wikipedia.org", engine).url, "https://en.wikipedia.org");
        compare(Logic.resolveInput("http://a.org", engine).url, "http://a.org");
        compare(Logic.resolveInput("about:blank", engine).url, "about:blank");
        compare(Logic.resolveInput("cats and dogs", engine).url, engine + "cats%20and%20dogs");
        compare(Logic.resolveInput("javascript:alert(1)", engine).error, "Browser can't open javascript: addresses");
        compare(Logic.resolveInput("data:text/html,x", engine).error, "Browser can't open data: addresses");
        compare(Logic.resolveInput("FILE:///etc/passwd", engine).error, "Browser can't open file: addresses");
        compare(Logic.resolveInput("cats", "ftp://x/?q=").error, "Browser can't open this address");
        compare(Logic.resolveInput("  ", engine).url, undefined);
        compare(Logic.resolveInput("localhost:8080", engine).url, "https://localhost:8080");
        compare(Logic.resolveInput("router:8080/admin", engine).url, "https://router:8080/admin");
        compare(Logic.resolveInput("localhost", engine).url, "https://localhost");
    }

    function test_homepageFromInput() {
        compare(Logic.homepageFromInput(" mine.org "), "https://mine.org");
        compare(Logic.homepageFromInput("http://a.org"), "http://a.org");
        compare(Logic.homepageFromInput("about:blank"), "about:blank");
        compare(Logic.homepageFromInput(""), "");
        compare(Logic.homepageFromInput("foo bar"), "");
        compare(Logic.homepageFromInput("foo"), "");
        compare(Logic.homepageFromInput("localhost:8080/x"), "https://localhost:8080/x");
        compare(Logic.homepageFromInput("example.com/a?b"), "https://example.com/a?b");
    }

    function test_suggestions() {
        const bookmarks = [{ url: "https://kde.org", title: "KDE" }];
        const history = [{ url: "https://kde.org", title: "KDE" }, { url: "https://qt.io", title: "Qt docs" }];
        compare(Logic.suggestions("", [], [], "Bing"), []);
        const s = Logic.suggestions("kde.org", bookmarks, history, "Bing");
        compare(s.map(e => e.kind), ["go", "search", "bookmark"]);
        compare(s[0].value, "https://kde.org");
        compare(s[1].title, "Search Bing for \"kde.org\"");
        const d = Logic.suggestions("docs", bookmarks, history, "Bing");
        compare(d.map(e => e.kind), ["search", "history"]);
        compare(d[1].title, "Qt docs");
        compare(d[1].subtitle, "https://qt.io");
    }

    function test_emptyQuerySuggestsBookmarksThenRecent() {
        const bookmarks = [{ url: "https://kde.org", title: "KDE" }];
        const history = [{ url: "https://old.org", title: "Old", timestamp: 1 }, { url: "https://kde.org", title: "KDE", timestamp: 9 }];
        for (let i = 0; i < 10; i++)
            history.push({ url: "https://n" + i + ".org", title: "", timestamp: 10 + i });
        const s = Logic.suggestions("  ", bookmarks, history, "Bing");
        compare(s[0].kind, "bookmark");
        compare(s[0].value, "https://kde.org");
        compare(s.slice(1).map(e => e.value), ["https://n9.org", "https://n8.org", "https://n7.org", "https://n6.org", "https://n5.org", "https://n4.org"]);
        verify(s.every(e => e.kind !== "search" && e.kind !== "go"));
    }

    function test_suggestionsCapAtEight() {
        const history = [];
        for (let i = 0; i < 20; i++)
            history.push({ url: "https://site" + i + ".org", title: "" });
        compare(Logic.suggestions("site", [], history, "X").length, 8);
    }

    function test_matches() {
        const list = [{ url: "https://a.org", title: "Alpha" }, { url: "https://b.org", title: "Beta" }];
        compare(Logic.matches(list, "").length, 2);
        compare(Logic.matches(list, "BETA")[0].url, "https://b.org");
        compare(Logic.matches(list, "a.org").length, 1);
    }

    function test_bookmarks() {
        let b = Logic.addBookmark([], "https://a.org", "", 5);
        compare(b, [{ url: "https://a.org", title: "https://a.org", timestamp: 5 }]);
        verify(Logic.isBookmarked(b, "https://a.org"));
        compare(Logic.addBookmark(b, "https://a.org", "Again", 6), b);
        b = Logic.removeBookmark(b, "https://a.org");
        compare(b.length, 0);
    }

    function test_addHistory() {
        let h = Logic.addHistory([], "https://a.org", "A", 1);
        h = Logic.addHistory(h, "https://b.org", "", 2);
        compare(h.map(e => e.url), ["https://b.org", "https://a.org"]);
        compare(h[0].title, "https://b.org");
        h = Logic.addHistory(h, "https://a.org", "", 3);
        compare(h[1].visitCount, 2);
        compare(h[1].timestamp, 3);
        compare(h[1].title, "A");
    }

    function test_historyCap() {
        let h = [];
        for (let i = 0; i < 105; i++)
            h = Logic.addHistory(h, "https://s" + i, "", i);
        compare(h.length, 100);
        compare(h[0].url, "https://s104");
    }

    function test_retitleAndRemoveHistory() {
        const h = [{ url: "https://a.org", title: "a" }];
        compare(Logic.retitleHistory(h, "https://a.org", "a"), h);
        compare(Logic.retitleHistory(h, "https://a.org", ""), h);
        compare(Logic.retitleHistory(h, "https://a.org", "New")[0].title, "New");
        compare(Logic.removeHistory(h, "https://a.org"), []);
    }

    function test_dateGroup() {
        const now = new Date(2026, 9, 12, 9, 0).getTime();
        compare(Logic.dateGroup(new Date(2026, 9, 12, 0, 5).getTime(), now), "Today");
        compare(Logic.dateGroup(new Date(2026, 9, 11, 23, 0).getTime(), now), "Yesterday");
        compare(Logic.dateGroup(new Date(2026, 9, 11, 0, 1).getTime(), now), "Yesterday");
        compare(Logic.dateGroup(new Date(2026, 9, 7, 12, 0).getTime(), now), "This week");
        compare(Logic.dateGroup(new Date(2026, 8, 12).getTime(), now), "Older");
    }

    function test_tabs() {
        const rows = Logic.restoreTabs(JSON.stringify([{ id: 4, url: "about:blank", title: "" }, { id: 2, url: "https://a.org", title: "A" }]), "https://home");
        compare(rows.length, 2);
        compare(rows[0].url, "https://home");
        compare(rows[0].title, "New tab");
        verify(!rows[0].isLoading);
        compare(Logic.nextTabId(rows), 5);
        compare(Logic.nextTabId([]), 1);
        compare(JSON.parse(Logic.saveTabs(rows)), [{ id: 4, url: "https://home", title: "New tab" }, { id: 2, url: "https://a.org", title: "A" }]);
        compare(Logic.restoreTabs("nope", "x"), []);
        const fresh = Logic.tabRow(1, "https://a.org", "", true);
        verify(fresh.isLoading && fresh.isNewTab);
        compare(fresh.loadProgress, 5);
    }

    function test_lookups() {
        compare(Logic.indexOfName(Logic.searchEngines, "Ecosia"), 4);
        compare(Logic.indexOfUrl(Logic.homepages, "about:blank"), 3);
        compare(Logic.indexOfUrl(Logic.homepages, "https://mine.org"), -1);
    }
}
