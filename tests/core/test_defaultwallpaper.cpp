#include <QSettings>
#include <QTemporaryDir>
#include <QTest>

#include "managers/settingsmanager.h"

class TestDefaultWallpaper : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    static void reset(const QString &wallpaper = {}) {
        QSettings s("marathon-os", "Marathon Shell");
        s.clear();
        if (!wallpaper.isEmpty())
            s.setValue("ui/wallpaperPath", wallpaper);
        s.sync();
    }

  private slots:
    void initTestCase() {
        QVERIFY(m_dir.isValid());
        qputenv("XDG_CONFIG_HOME", m_dir.path().toUtf8());
    }

    void freshInstallGetsTidewater() {
        reset();
        SettingsManager m;
        QVERIFY2(m.wallpaperPath().endsWith("wallpapers/tidewater.jpg"), qPrintable(m.wallpaperPath()));
    }

    void chosenWallpaperIsKept() {
        reset("file:///usr/share/marathon-shell/wallpapers/slate-aurora.svg");
        SettingsManager m;
        QCOMPARE(m.wallpaperPath(), QString("file:///usr/share/marathon-shell/wallpapers/slate-aurora.svg"));
    }
};

QTEST_GUILESS_MAIN(TestDefaultWallpaper)
#include "test_defaultwallpaper.moc"
