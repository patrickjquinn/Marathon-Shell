#include <QTest>
#include <QTemporaryDir>

#include "desktopfileparser.h"

class TestDesktopFileParser : public QObject {
    Q_OBJECT

    static void write(const QString &path, const QByteArray &text) {
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(text);
    }

  private slots:
    // As Waydroid's user_manager writes an Android app's entry.
    void waydroidAppIsAMobileNativeApp() {
        QTemporaryDir dir;
        const QString icon = dir.filePath("org.fdroid.fdroid.png");
        write(icon, "png");
        write(dir.filePath("waydroid.org.fdroid.fdroid.desktop"),
              "[Desktop Entry]\n"
              "Type=Application\n"
              "Name=F-Droid\n"
              "Exec=waydroid app launch org.fdroid.fdroid\n"
              "Icon=" + icon.toUtf8() + "\n"
              "Categories=X-WayDroid-App;\n"
              "X-Purism-FormFactor=Workstation;Mobile;\n"
              "Actions=app-settings;\n"
              "\n"
              "[Desktop Action app-settings]\n"
              "Name=App Settings\n"
              "Exec=waydroid app intent android.settings.APPLICATION_DETAILS_SETTINGS "
              "package:org.fdroid.fdroid\n");
        write(dir.filePath("waydroid.com.android.settings.desktop"),
              "[Desktop Entry]\n"
              "Type=Application\n"
              "Name=Settings\n"
              "Exec=waydroid app launch com.android.settings\n"
              "X-Purism-FormFactor=Workstation;Mobile;\n"
              "NoDisplay=true\n");

        DesktopFileParser  parser;
        const QVariantList apps = parser.scanApplications({dir.path()}, true);
        QCOMPARE(apps.size(), 1);
        const QVariantMap app = apps.first().toMap();
        QCOMPARE(app.value("id").toString(), QStringLiteral("waydroid.org.fdroid.fdroid"));
        QCOMPARE(app.value("name").toString(), QStringLiteral("F-Droid"));
        QCOMPARE(app.value("type").toString(), QStringLiteral("native"));
        QCOMPARE(app.value("exec").toString(),
                 QStringLiteral("waydroid app launch org.fdroid.fdroid"));
        QCOMPARE(app.value("icon").toString(), icon);
    }
};

QTEST_GUILESS_MAIN(TestDesktopFileParser)
#include "test_desktopfileparser.moc"
