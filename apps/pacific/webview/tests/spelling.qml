// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Spell-checking test: for English (hunspell) and Finnish (Voikko), a
// misspelt word typed into a textarea is marked, a long press (here a right
// click) on it offers suggestions, and applying one replaces the word.
//
//   tools/host-run.sh <prefix> <build> qml6 tests/spelling.qml
//   /usr/libexec/pacific/pacific-env.sh qml6 spelling.qml          (phone)
//
// Prints "spelling: PASS|FAIL <step>"; exits 0 when all passed.
import QtQuick
import QtQuick.Window
import Shipwright.Pacific.WebView 1.0

Window {
    id: root

    property int failures: 0
    property var menu: null
    // A screenshot of the marked word (red underline), for a human to check.
    readonly property string shot: "/tmp/pacific-spelling.png"

    function check(name, ok, detail) {
        console.warn("spelling: " + (ok ? "PASS " : "FAIL ") + name + (detail !== undefined ? " (" + detail + ")" : ""));
        if (!ok)
            failures++;
    }

    function finish() {
        console.warn("spelling: " + (failures ? failures + " failure(s)" : "all passed"));
        Qt.exit(failures ? 1 : 0);
    }

    function after(ms, fn) {
        const t = Qt.createQmlObject("import QtQuick; Timer {}", root);
        t.interval = ms;
        t.triggered.connect(function () {
            fn();
            t.destroy();
        });
        t.start();
    }

    width: 540
    height: 600
    visible: true

    WebView {
        id: view

        anchors.fill: parent
        url: "data:text/html;charset=utf-8,<body style='font:24px sans-serif;margin:10px'>" + "<textarea id=t style='width:500px;height:200px;font:28px sans-serif'></textarea></body>"

        onLoadingChanged: function (request) {
            if (request.status !== LoadRequest.Succeeded)
                return;
            root.check("spell checking on", WebEngine.spellChecking && WebEngine.spellCheckingLanguages.length > 0, WebEngine.spellCheckingLanguages.join(","));
            root.check("dictionaries packaged", WebEngine.availableSpellCheckingLanguages.indexOf("en_GB") >= 0 && WebEngine.availableSpellCheckingLanguages.indexOf("de_DE") >= 0, WebEngine.availableSpellCheckingLanguages.join(","));
            root.check("profile mirrors engine", view.profile.spellChecking === WebEngine.spellChecking);
            root.runCase(0);
        }

        onContextMenuRequested: function (info) {
            root.menu = info;
        }
    }

    // Each case: language, text typed, the text before the misspelt word,
    // the word, the suggestion to apply. Finnish comes from Voikko.
    readonly property var cases: [
        {
            lang: "en_GB",
            text: "This sentence has a mistaek ",
            before: "This sentence has a ",
            word: "mistaek",
            fix: "mistake"
        },
        {
            lang: "fi_FI",
            text: "Näin on kisssa ",
            before: "Näin on ",
            word: "kisssa",
            fix: "kissa"
        },
    ]

    function runCase(i) {
        if (i >= cases.length) {
            finish();
            return;
        }
        const c = cases[i];
        check(c.lang + " available", WebEngine.availableSpellCheckingLanguages.indexOf(c.lang) >= 0);
        WebEngine.spellCheckingLanguages = [c.lang];
        menu = null;
        view.runJavaScript("document.getElementById('t').value=''", function () {
            view.agentSnapshot({}, function (snap) {
                view.agentType(snap.elements[0].id, c.text, function () {
                    after(800, function () {
                        rightClick(i);
                    });
                });
            });
        });
    }

    function rightClick(i) {
        const c = cases[i];
        if (i === 0)
            root.contentItem.grabToImage(function (img) {
                img.saveToFile(root.shot);
            });
        // Aim inside the word: measure the text before it in the page.
        view.runJavaScriptInWorld("(function(b,w){var c=document.createElement('canvas').getContext('2d');c.font='28px sans-serif';" + "var t=document.getElementById('t');var cs=getComputedStyle(t);" + "var x=t.getBoundingClientRect().left+parseFloat(cs.paddingLeft)+parseFloat(cs.borderLeftWidth)" + "+c.measureText(b).width+c.measureText(w.slice(0,3)).width;" + "var y=t.getBoundingClientRect().top+parseFloat(cs.paddingTop)+parseFloat(cs.borderTopWidth)+16;" + "return [x,y];})(" + JSON.stringify(c.before) + "," + JSON.stringify(c.word) + ")", "pacific", function (p) {
            view.contextMenuAt(p[0], p[1]);
            after(800, function () {
                afterMenu(i);
            });
        });
    }

    function afterMenu(i) {
        const c = cases[i];
        check(c.lang + " context menu on the word", menu !== null);
        if (!menu) {
            runCase(i + 1);
            return;
        }
        check(c.lang + " word marked misspelt", menu.misspelled === true);
        const index = menu.spellingSuggestions ? menu.spellingSuggestions.indexOf(c.fix) : -1;
        check(c.lang + " suggestions offered", index >= 0, menu.spellingSuggestions ? menu.spellingSuggestions.join(",") : "none");
        const applied = index >= 0 && view.applySpellingSuggestion(index);
        check(c.lang + " suggestion applied", applied, "index " + index);
        after(400, function () {
            view.runJavaScript("document.getElementById('t').value", function (v) {
                check(c.lang + " word replaced", v.indexOf(" " + c.fix + " ") >= 0, v);
                runCase(i + 1);
            });
        });
    }

    Timer {
        interval: 45000
        running: true
        onTriggered: {
            console.warn("spelling: FAIL timeout");
            Qt.exit(2);
        }
    }
}
