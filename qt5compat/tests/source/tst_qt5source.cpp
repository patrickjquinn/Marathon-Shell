// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keel/qt5compat's Qt 5 source rewrite (src/qt5source.h): the tokenizer-level
// rewrite, and the URL interceptor on a real engine.

#include "qt5source.h"

#include <QDir>
#include <QFile>
#include <QJSEngine>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using KeelQt5Compat::rewriteQt5Source;

class TestQt5Source : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase()
    {
        QVERIFY(m_cache.isValid());
        qputenv("KEEL_QT5COMPAT_CACHE", QFile::encodeName(m_cache.path()));
    }

    void rewrite_data()
    {
        QTest::addColumn<QString>("in");
        QTest::addColumn<QString>("out");

        // Rewritten: a declarator without initializer.
        QTest::newRow("plain") << "const x;" << "var   x;";
        QTest::newRow("no semicolon (ASI)") << "const items\nif (a) items = 1" << "var   items\nif (a) items = 1";
        QTest::newRow("first of two") << "const a, b = 1;" << "var   a, b = 1;";
        QTest::newRow("second of two") << "const a = f(1, 2), b;" << "var   a = f(1, 2), b;";
        QTest::newRow("initializer with object and comma")
            << "const a = { p: 1, q: [2, 3] }, b\nfoo()" << "var   a = { p: 1, q: [2, 3] }, b\nfoo()";
        QTest::newRow("in a function in QML")
            << "Item {\n    function f() {\n        const items\n        items = []\n    }\n}"
            << "Item {\n    function f() {\n        var   items\n        items = []\n    }\n}";
        QTest::newRow("in a QML signal handler") << "onClicked: { const r; r = 2 }" << "onClicked: { var   r; r = 2 }";
        QTest::newRow("nested function") << "function f() { return function() { const y; } }"
                                         << "function f() { return function() { var   y; } }";
        QTest::newRow("in template substitution") << "s = `${(function() { const t; t = 1; return t })()}`"
                                                  << "s = `${(function() { var   t; t = 1; return t })()}`";
        QTest::newRow("after regex literal") << "var r = /const x;/g; const z;" << "var r = /const x;/g; var   z;";
        QTest::newRow("several") << "const a;\nconst b = 1;\nconst c;" << "var   a;\nconst b = 1;\nvar   c;";
        QTest::newRow("classic for head") << "for (const i; ;) {}" << "for (var   i; ;) {}";

        // Unchanged: valid Qt 6 code, or not code.
        QTest::newRow("initialized") << "const x = 1;" << "const x = 1;";
        QTest::newRow("initialized, two") << "const a = 1, b = 2;" << "const a = 1, b = 2;";
        QTest::newRow("initializer on next line") << "const x =\n    1\nfoo()" << "const x =\n    1\nfoo()";
        QTest::newRow("initializer continues") << "const x = a\n    + b, y = 2" << "const x = a\n    + b, y = 2";
        QTest::newRow("for of") << "for (const x of y) {}" << "for (const x of y) {}";
        QTest::newRow("for in") << "for (const k in o) {}" << "for (const k in o) {}";
        QTest::newRow("for await of") << "for await (const x of y) {}" << "for await (const x of y) {}";
        QTest::newRow("for of pattern") << "for (const [k, v] of m) {}" << "for (const [k, v] of m) {}";
        QTest::newRow("classic for initialized") << "for (const i = 0; i < 1;) {}" << "for (const i = 0; i < 1;) {}";
        QTest::newRow("destructuring") << "const { a, b } = o; const [c] = l;" << "const { a, b } = o; const [c] = l;";
        QTest::newRow("double-quoted string") << "s = \"const x;\"" << "s = \"const x;\"";
        QTest::newRow("single-quoted string") << "s = 'const x;'" << "s = 'const x;'";
        QTest::newRow("escaped quote in string") << "s = 'a\\' const x;'" << "s = 'a\\' const x;'";
        QTest::newRow("template literal") << "s = `const x;`" << "s = `const x;`";
        QTest::newRow("template with substitution text") << "s = `${a} const x; ${b}`" << "s = `${a} const x; ${b}`";
        QTest::newRow("nested template") << "s = `${`const x;`}`" << "s = `${`const x;`}`";
        QTest::newRow("line comment") << "// const x;\nfoo()" << "// const x;\nfoo()";
        QTest::newRow("block comment") << "/* const x;\n const y; */" << "/* const x;\n const y; */";
        QTest::newRow("regex literal") << "r = /const x;/" << "r = /const x;/";
        QTest::newRow("regex with class") << "r = /[/]const x;/" << "r = /[/]const x;/";
        QTest::newRow("division is not a regex") << "a = b / 2; c = d / 3" << "a = b / 2; c = d / 3";
        QTest::newRow("member named const") << "a.const; b?.const;" << "a.const; b?.const;";
        QTest::newRow("property key") << "o = { const: 1 }" << "o = { const: 1 }";
        QTest::newRow("identifier containing const") << "constant; myconst;" << "constant; myconst;";
        QTest::newRow("QML property") << "property string s: \"const x;\"" << "property string s: \"const x;\"";
    }

    void rewrite()
    {
        QFETCH(QString, in);
        QFETCH(QString, out);
        const auto r = rewriteQt5Source(in);
        QCOMPARE(r.source, out);
        QCOMPARE(r.changed(), in != out);
        QCOMPARE(r.source.size(), in.size()); // columns do not move
    }

    void rewriteCounts()
    {
        QCOMPARE(rewriteQt5Source(u"const a;\nconst b;\nconst c = 1;").constDeclarations, 2);
        QCOMPARE(rewriteQt5Source(u"").constDeclarations, 0);
        QCOMPARE(rewriteQt5Source(u"`unterminated ${").constDeclarations, 0); // no crash
        QCOMPARE(rewriteQt5Source(u"'unterminated\nconst x;").constDeclarations, 1);
    }

    // The rewritten code compiles on Qt 6 and behaves as Qt 5.6 ran it.
    void rewrittenRuns()
    {
        const QString src = QStringLiteral(
            "(function(regional) {\n"
            "    const items\n"
            "    if (regional) {\n"
            "        const extra = ['r']\n"
            "        items = ['n'].concat(extra)\n"
            "    } else {\n"
            "        items = ['n']\n"
            "    }\n"
            "    return items.join(',')\n"
            "})");
        QJSEngine js;
        QVERIFY(js.evaluate(src).isError()); // Qt 6 rejects the original
        const QJSValue f = js.evaluate(rewriteQt5Source(src).source);
        QVERIFY2(f.isCallable(), qPrintable(f.toString()));
        QCOMPARE(f.call({true}).toString(), QStringLiteral("n,r"));
        QCOMPARE(f.call({false}).toString(), QStringLiteral("n"));
    }

    // On an engine: app files load from rewritten copies, relative imports
    // and errors keep the original location, files outside the roots are
    // not touched.
    void interceptor()
    {
        QTemporaryDir app;
        QVERIFY(app.isValid());
        QDir dir(app.path());
        QVERIFY(dir.mkpath(QStringLiteral("qml/pages")) && dir.mkpath(QStringLiteral("qml/components")));
        write(dir.filePath(QStringLiteral("qml/components/Model.qml")),
              "import QtQuick 2.0\n"
              "import \"../js/util.js\" as Util\n"
              "QtObject {\n"
              "    property var items\n"
              "    function load(regional) {\n"
              "        const items\n"
              "        if (regional) items = Util.regional()\n"
              "        else items = ['n']\n"
              "        this.items = items\n"
              "    }\n"
              "}\n");
        QVERIFY(dir.mkpath(QStringLiteral("qml/js")));
        write(dir.filePath(QStringLiteral("qml/js/util.js")),
              "function regional() { const r, s = 1; r = ['r']; return r }\n");
        write(dir.filePath(QStringLiteral("qml/pages/Page.qml")),
              "import QtQuick 2.0\n"
              "import \"../components\"\n"
              "Item {\n"
              "    property string base: Qt.resolvedUrl(\".\")\n"
              "    property var model: Model { }\n"
              "    Component.onCompleted: model.load(true)\n"
              "}\n");
        const QUrl page = QUrl::fromLocalFile(dir.filePath(QStringLiteral("qml/pages/Page.qml")));

        {
            // Without the rewrite Qt 6 refuses the file.
            QQmlEngine engine;
            QQmlComponent c(&engine, page);
            QVERIFY(c.isError());
            QVERIFY(c.errorString().contains(QStringLiteral("Missing initializer in const declaration")));
        }

        QQmlEngine engine;
        KeelQt5Compat::installSourceCompat(&engine, {dir.filePath(QStringLiteral("qml"))});
        KeelQt5Compat::installSourceCompat(&engine, {dir.filePath(QStringLiteral("qml"))}); // idempotent
        QCOMPARE(engine.urlInterceptors().size(), 1);
        QQmlComponent c(&engine, page);
#if QT_VERSION >= QT_VERSION_CHECK(6, 10, 0)
        // Up to Qt 6.8 a type keeps its original URL as the base for relative
        // URLs and only its data comes from the cached copy. From Qt 6.10
        // QQmlImports looks types up by the intercepted URL, so the cached
        // copy's directory becomes the base and Model.qml's "../js/util.js"
        // is not found. Known gap (COMPATIBILITY.md); the phone's Qt is 6.8.
        QEXPECT_FAIL("", "Qt 6.10+ resolves relative URLs against the rewritten copy", Abort);
#endif
        QVERIFY2(!c.isError(), qPrintable(c.errorString()));
        std::unique_ptr<QObject> o(c.create());
        QVERIFY(o);
        // Relative URLs still resolve against the app's directory.
        QCOMPARE(o->property("base").toString(),
                 QUrl::fromLocalFile(dir.filePath(QStringLiteral("qml/pages/"))).toString());
        auto *model = o->property("model").value<QObject *>();
        QVERIFY(model);
        QCOMPARE(model->property("items").toStringList(), QStringList{QStringLiteral("r")});

        const auto files = KeelQt5Compat::rewrittenFiles(&engine);
        QCOMPARE(files.size(), 2); // Model.qml and util.js; Page.qml needs nothing
        for (const auto &f : files) {
            QVERIFY(f.cachedPath.startsWith(m_cache.path()));
            QVERIFY(QFile::exists(f.cachedPath));
            QCOMPARE(QFileInfo(f.cachedPath).fileName(), QFileInfo(f.url.toLocalFile()).fileName());
        }

        // A file outside the roots stays as it is.
        QTemporaryDir other;
        write(other.filePath(QStringLiteral("Other.qml")),
              "import QtQuick 2.0\nItem { function f() { const x; } }\n");
        QQmlComponent outside(&engine, QUrl::fromLocalFile(other.filePath(QStringLiteral("Other.qml"))));
        QVERIFY(outside.isError());
        // Compile errors in a rewritten file name the cached copy (Qt reports
        // the physical URL), at the original line and column.
        write(dir.filePath(QStringLiteral("qml/Broken.qml")),
              "import QtQuick 2.0\nItem {\n    function f() { const x; return x }\n    property int p: ]\n}\n");
        QQmlComponent broken(&engine, QUrl::fromLocalFile(dir.filePath(QStringLiteral("qml/Broken.qml"))));
        QVERIFY(broken.isError());
        const QQmlError error = broken.errors().constFirst();
        const auto rewritten = KeelQt5Compat::rewrittenFiles(&engine);
        QCOMPARE(rewritten.constLast().url, QUrl::fromLocalFile(dir.filePath(QStringLiteral("qml/Broken.qml"))));
        QCOMPARE(error.url(), QUrl::fromLocalFile(rewritten.constLast().cachedPath));
        QCOMPARE(error.line(), 4);
        QCOMPARE(error.column(), 21);
    }

    void optOut()
    {
        qputenv("KEEL_QT5COMPAT_SOURCE", "0");
        QVERIFY(!KeelQt5Compat::sourceCompatEnabled());
        QQmlEngine engine;
        KeelQt5Compat::installSourceCompat(&engine, {QDir::tempPath()});
        QVERIFY(engine.urlInterceptors().isEmpty());
        qunsetenv("KEEL_QT5COMPAT_SOURCE");
        QVERIFY(KeelQt5Compat::sourceCompatEnabled());
    }

private:
    static void write(const QString &path, const char *content)
    {
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(content);
    }

    QTemporaryDir m_cache;
};

QTEST_MAIN(TestQt5Source)
#include "tst_qt5source.moc"
