#include <QTest>
#include <QTemporaryDir>
#include <QSet>

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

    // The Store's AppStream verdict (phone-apps.json) lets an app without a
    // form-factor hint onto the grid; AppStream ids may carry ".desktop".
    void anAppTheStoreCallsPhoneReadyIsShown() {
        QTemporaryDir dir;
        write(dir.filePath("org.gnome.Podcasts.desktop"),
              "[Desktop Entry]\nType=Application\nName=Podcasts\nExec=gnome-podcasts\n");
        write(dir.filePath("com.example.Old.desktop"),
              "[Desktop Entry]\nType=Application\nName=Old\nExec=old\n");
        write(dir.filePath("org.example.Desk.desktop"),
              "[Desktop Entry]\nType=Application\nName=Desk\nExec=desk\n");
        write(dir.filePath("foot.desktop"), "[Desktop Entry]\nType=Application\nName=Foot\nExec=foot\n");
        write(dir.filePath("phone-apps.json"),
              "{\"source\":1,\"apps\":[\"org.gnome.Podcasts\",\"com.example.Old.desktop\",\"foot\"],\"ts\":2}\n");

        DesktopFileParser parser;
        QCOMPARE(parser.scanApplications({dir.path()}, true).size(), 0);

        const QSet<QString> phoneApps = DesktopFileParser::readPhoneApps(dir.filePath("phone-apps.json"));
        QCOMPARE(phoneApps, (QSet<QString>{"org.gnome.Podcasts", "com.example.Old", "foot"}));
        parser.setPhoneApps(phoneApps);
        QStringList names;
        const QVariantList apps = parser.scanApplications({dir.path()}, true);
        for (const QVariant &app : apps)
            names << app.toMap().value("name").toString();
        names.sort();
        QCOMPARE(names, (QStringList{"Old", "Podcasts"}));
        QVERIFY(DesktopFileParser::readPhoneApps(dir.filePath("missing.json")).isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestDesktopFileParser)
#include "test_desktopfileparser.moc"
