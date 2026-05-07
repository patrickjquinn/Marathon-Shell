#include <QTest>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include "../../shell/src/components/desktopfileparser.h"

class TestDesktopFileParser : public QObject {
    Q_OBJECT

  private:
    bool writeFile(const QString &path, const QByteArray &data) {
        QDir().mkpath(QFileInfo(path).path());
        QFile f(path);
        if (!f.open(QIODevice::WriteOnly))
            return false;
        f.write(data);
        return true;
    }

    QByteArray basicDesktop(const QString &name, const QString &exec, const QString &extra = "") {
        return ("[Desktop Entry]\nType=Application\nName=" + name + "\nExec=" + exec + "\n" +
                extra + "\n")
            .toUtf8();
    }

  private slots:

    // === CONTRACT: Valid .desktop file produces correct fields ===

    void parsesValidDesktopFile() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/test.desktop",
                  "[Desktop Entry]\n"
                  "Type=Application\n"
                  "Name=Test App\n"
                  "Comment=A test application\n"
                  "Exec=test-app --flag\n"
                  "Icon=test-icon\n"
                  "Categories=Utility;Development;\n"
                  "Terminal=false\n");

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/test.desktop");

        QVERIFY(!app.isEmpty());
        QCOMPARE(app["name"].toString(), QString("Test App"));
        QCOMPARE(app["comment"].toString(), QString("A test application"));
        QCOMPARE(app["type"].toString(), QString("native"));
        QVERIFY(!app["terminal"].toBool());
        QCOMPARE(app["id"].toString(), QString("test"));

        QStringList cats = app["categories"].toStringList();
        QVERIFY(cats.contains("Utility"));
        QVERIFY(cats.contains("Development"));
    }

    // === CONTRACT: NoDisplay=true must be filtered out ===

    void noDisplayAppIsFiltered() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/hidden.desktop",
                  basicDesktop("Hidden", "hidden-app", "NoDisplay=true"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/hidden.desktop");

        QVERIFY2(app.isEmpty(), "NoDisplay=true apps must be filtered out");
    }

    // === CONTRACT: Hidden=true must be filtered out ===

    void hiddenAppIsFiltered() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/secret.desktop",
                  basicDesktop("Secret", "secret-app", "Hidden=true"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/secret.desktop");

        QVERIFY2(app.isEmpty(), "Hidden=true apps must be filtered out");
    }

    // === CONTRACT: Type!=Application must be rejected ===

    void nonApplicationTypeRejected() {
        QTemporaryDir dir;
        writeFile(
            dir.path() + "/link.desktop",
            "[Desktop Entry]\nType=Link\nName=A Link\nExec=something\nURL=https://example.com\n");

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/link.desktop");

        QVERIFY2(app.isEmpty(), "Type=Link must be rejected");
    }

    // === CONTRACT: Missing Name must be rejected ===

    void missingNameRejected() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/noname.desktop",
                  "[Desktop Entry]\nType=Application\nExec=something\n");

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/noname.desktop");

        QVERIFY2(app.isEmpty(), "Desktop file without Name must be rejected");
    }

    // === CONTRACT: Missing Exec must be rejected ===

    void missingExecRejected() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/noexec.desktop",
                  "[Desktop Entry]\nType=Application\nName=No Exec\n");

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/noexec.desktop");

        QVERIFY2(app.isEmpty(), "Desktop file without Exec must be rejected");
    }

    // === CONTRACT: Exec line field codes (%f, %u, etc) must be stripped ===

    void execFieldCodesAreStripped() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/app.desktop", basicDesktop("App", "myapp %U --verbose %f"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/app.desktop");

        QString           exec = app["exec"].toString();
        QVERIFY2(!exec.contains("%U"), "Exec field code %U was not stripped");
        QVERIFY2(!exec.contains("%f"), "Exec field code %f was not stripped");
        QVERIFY(exec.contains("myapp"));
        QVERIFY(exec.contains("--verbose"));
    }

    // === CONTRACT: Window flag removal must not corrupt binary names ===
    // Only exact whitespace-delimited tokens should be stripped.

    void windowFlagRemovalDoesNotCorruptExec() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/app.desktop",
                  basicDesktop("App", "my-new-window-app --some-flag"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/app.desktop");

        QString           exec = app["exec"].toString();
        QVERIFY2(exec.contains("my-new-window-app"),
                 qPrintable("Exec line corrupted: got '" + exec + "'"));
        QVERIFY(exec.contains("--some-flag"));
    }

    // === CONTRACT: Actual window flags ARE removed ===

    void actualWindowFlagsAreRemoved() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/browser.desktop",
                  basicDesktop("Browser", "firefox --new-window %u"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/browser.desktop");

        QString           exec = app["exec"].toString();
        QVERIFY2(!exec.contains("--new-window"),
                 "Window flag --new-window must be stripped from exec");
        QVERIFY(exec.contains("firefox"));
    }

    // === CONTRACT: Absolute paths in Exec are simplified to binary name ===

    void absolutePathsSimplified() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/abs.desktop", basicDesktop("Abs", "/usr/bin/my-program --arg1"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/abs.desktop");

        QString           exec = app["exec"].toString();
        QVERIFY2(!exec.contains("/usr/bin/"), "Absolute path should be simplified to binary name");
        QVERIFY(exec.startsWith("my-program"));
    }

    // === CONTRACT: gapplication launch is converted to binary name ===

    void gapplicationLaunchConverted() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/gcalc.desktop",
                  basicDesktop("Calc", "gapplication launch org.gnome.Calculator"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/gcalc.desktop");

        QString           exec = app["exec"].toString();
        QVERIFY2(!exec.contains("gapplication"),
                 "gapplication launch should be converted to binary");
        QVERIFY2(exec == "gnome-calculator",
                 qPrintable("Expected 'gnome-calculator', got '" + exec + "'"));
    }

    // === CONTRACT: Flatpak apps get FLATPAK: prefix ===

    void flatpakAppsPrefixed() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/flatpak.desktop",
                  basicDesktop("FP App", "flatpak run org.test.App"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/flatpak.desktop");

        QVERIFY(app["exec"].toString().startsWith("FLATPAK:"));
    }

    // === CONTRACT: Snap apps get SNAP: prefix ===

    void snapAppsPrefixed() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/snap.desktop", basicDesktop("Snap App", "snap run mysnap"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/snap.desktop");

        QVERIFY(app["exec"].toString().startsWith("SNAP:"));
    }

    // === CONTRACT: Comments and blank lines are ignored ===

    void commentsIgnored() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/commented.desktop",
                  "[Desktop Entry]\n"
                  "# This is a comment\n"
                  "Type=Application\n"
                  "\n"
                  "Name=Commented App\n"
                  "# Another comment\n"
                  "Exec=commented-app\n");

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/commented.desktop");

        QVERIFY(!app.isEmpty());
        QCOMPARE(app["name"].toString(), QString("Commented App"));
    }

    // === CONTRACT: Only [Desktop Entry] section is parsed ===

    void onlyDesktopEntrySectionParsed() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/sections.desktop",
                  "[Desktop Entry]\n"
                  "Type=Application\n"
                  "Name=Real Name\n"
                  "Exec=real-app\n"
                  "\n"
                  "[Desktop Action New]\n"
                  "Name=Action Name\n"
                  "Exec=action-app\n");

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/sections.desktop");

        QCOMPARE(app["name"].toString(), QString("Real Name"));
        QCOMPARE(app["exec"].toString(), QString("real-app"));
    }

    // === CONTRACT: Mobile-friendly detection via X-Purism-FormFactor ===

    void mobileFriendlyViaPurism() {
        QTemporaryDir dir;
        writeFile(
            dir.path() + "/mobile.desktop",
            basicDesktop("Mobile App", "mobile-app", "X-Purism-FormFactor=Workstation;Mobile;"));

        DesktopFileParser parser;
        QVariantList      apps = parser.scanApplications({dir.path()}, true);

        QCOMPARE(apps.count(), 1);
    }

    // === CONTRACT: Non-mobile apps are filtered with mobile filter ===

    void nonMobileFilteredOut() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/desktop-only.desktop", basicDesktop("Desktop App", "desktop-app"));

        DesktopFileParser parser;
        QVariantList      filtered = parser.scanApplications({dir.path()}, true);
        QVariantList      all      = parser.scanApplications({dir.path()}, false);

        QCOMPARE(filtered.count(), 0);
        QCOMPARE(all.count(), 1);
    }

    // === CONTRACT: All missing icon paths resolve to the same fallback ===

    void iconFallbackIsConsistent() {
        DesktopFileParser parser;

        QString           emptyResult   = parser.resolveIconPath("");
        QString           missingResult = parser.resolveIconPath("nonexistent-icon-xyz-12345");
        QString           absResult     = parser.resolveIconPath("/nonexistent/icon.png");

        QCOMPARE(emptyResult, missingResult);
        QCOMPARE(emptyResult, absResult);
        QCOMPARE(emptyResult, QString("layout-grid"));
    }

    // === CONTRACT: Nonexistent file returns empty map ===

    void nonexistentFileReturnsEmpty() {
        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile("/nonexistent/path.desktop");
        QVERIFY(app.isEmpty());
    }

    // === CONTRACT: Terminal=true is preserved ===

    void terminalFlagPreserved() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/term.desktop",
                  basicDesktop("Terminal App", "bash", "Terminal=true"));

        DesktopFileParser parser;
        QVariantMap       app = parser.parseDesktopFile(dir.path() + "/term.desktop");

        QVERIFY2(app["terminal"].toBool(), "Terminal=true must be preserved");
    }

    // === CONTRACT: ID is derived from filename, not manifest ===

    void idDerivedFromFilename() {
        QTemporaryDir dir;
        writeFile(dir.path() + "/org.gnome.Calculator.desktop",
                  basicDesktop("Calculator", "gnome-calculator"));

        DesktopFileParser parser;
        QVariantMap app = parser.parseDesktopFile(dir.path() + "/org.gnome.Calculator.desktop");

        QCOMPARE(app["id"].toString(), QString("org.gnome.Calculator"));
    }
};

QTEST_MAIN(TestDesktopFileParser)
#include "test_desktopfileparser.moc"
