// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

// The UI's pure helpers (qml/js/logic.js).

import QtQuick
import QtTest
import "../qml/js/logic.js" as Logic

TestCase {
    name: "logic"

    function test_hosts_and_display() {
        compare(Logic.host("https://www.Example.com/a?b"), "example.com")
        compare(Logic.host("https://user@host.example:8443/"), "host.example")
        compare(Logic.host("about:blank"), "")
        compare(Logic.displayUrl("https://news.example/x", "News"), "news.example")
        compare(Logic.displayUrl("about:blank", "x"), "")
        compare(Logic.displayUrl("", "x"), "")
        compare(Logic.displayUrl("file:///home/u/cache/reader/tab-3.html", "Article"), "Article")
        verify(Logic.insecure("http://a.example/"))
        verify(!Logic.insecure("https://a.example/"))
        verify(Logic.isReaderUrl("file:///c/reader/tab-12.html"))
        verify(!Logic.isReaderUrl("https://e.example/reader/tab-1.html"))
    }

    function test_initials_escape_size() {
        compare(Logic.initial("Title", "https://www.sailfishos.org/"), "S")
        compare(Logic.initial("", ""), "?")
        compare(Logic.escape("<b>a & \"b\"</b>"), "&lt;b&gt;a &amp; &quot;b&quot;&lt;/b&gt;")
        compare(Logic.size(512), "512 B")
        compare(Logic.size(1400000), (1.4).toLocaleString(Qt.locale(), "f", 1) + " MB")
        compare(Logic.size(25000000), "25 MB")
        compare(Logic.size(-1), "")
    }

    function test_swipes_and_zoom() {
        compare(Logic.swipeStep(-120, 100), 1)
        compare(Logic.swipeStep(130, 100), -1)
        compare(Logic.swipeStep(40, 100), 0)
        compare(Logic.zoomStep(1.0, 1), 1.1)
        compare(Logic.zoomStep(1.0, -1), 0.9)
        compare(Logic.zoomStep(3.0, 1), 3.0)
        compare(Logic.zoomStep(0.5, -1), 0.5)
        compare(Logic.zoomStep(1.3, 1), 1.5)
    }

    function test_permissions_and_clearing() {
        compare(Logic.permissionSetting(0), "perm.location")
        compare(Logic.permissionSetting(1), "perm.camera")
        compare(Logic.permissionSetting(3), "")
        compare(Logic.permissionSetting(99), "")
        var types = { cookies: 1, cache: 2, localStorage: 4, indexedDb: 8, serviceWorkers: 16 }
        compare(Logic.clearTypes({ cookies_and_site_data: true, cache: false }, types), 1 | 4 | 8 | 16)
        compare(Logic.clearTypes({ cookies_and_site_data: false, cache: true }, types), 2)
        compare(Logic.sinceSeconds(0, 5000), 0)
        compare(Logic.sinceSeconds(1000, 3601000), 3600)
        compare(Logic.ago(0, 30000), "now")
        compare(Logic.ago(0, 7200000), "2 h")
    }

    function test_bar_text_and_hue() {
        compare(Logic.barText("https://en.wikipedia.org/wiki/X", "X", "wikipedia.org"), "wikipedia.org")
        compare(Logic.barText("about:blank", "", ""), "")
        verify(Logic.hostHue("https://a.example/") >= 0 && Logic.hostHue("https://a.example/") < 1)
        compare(Logic.hostHue("https://www.a.example/x"), Logic.hostHue("https://a.example/y"))
    }

    function test_language_names() {
        compare(Logic.languageName("de_DE"), "Deutsch")
        compare(Logic.languageName("fi_FI"), "Suomi")
        verify(Logic.languageName("en_GB").indexOf("English") >= 0)
        compare(Logic.languageName("zz_ZZ"), "zz_ZZ")
    }

    function test_file_icons() {
        compare(Logic.fileIcon("sailfish-manual.pdf"), "icon-m-file-pdf-light")
        compare(Logic.fileIcon("big-map.ZIP"), "icon-m-file-compressed")
        compare(Logic.fileIcon("README"), "icon-m-file-other-light")
    }

    function test_initials() {
        compare(Logic.initial("Sailfish OS - Wikipedia", "https://en.wikipedia.org/wiki/Sailfish_OS"), "W")
        compare(Logic.initial("", "https://m.example.org/"), "E")
        compare(Logic.initial("Harbour", ""), "H")
    }
}
