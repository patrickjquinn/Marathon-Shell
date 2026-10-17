#include <QSettings>
#include <QTemporaryDir>
#include <QTest>

#include "managers/settingsmanager.h"
#include "services/wallpaperstore.h"

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

    void freshInstallGetsMeridian() {
        reset();
        SettingsManager m;
        QVERIFY2(m.wallpaperPath().endsWith("wallpapers/meridian.jpg"), qPrintable(m.wallpaperPath()));
    }

    void chosenWallpaperIsKept() {
        reset("file:///usr/share/marathon-shell/wallpapers/slate-aurora.svg");
        SettingsManager m;
        QCOMPARE(m.wallpaperPath(), QString("file:///usr/share/marathon-shell/wallpapers/slate-aurora.svg"));
    }

    void auroraNameIsUtf8() {
        reset();
        SettingsManager m;
        WallpaperStore  store(&m);
        QString name;
        for (const QVariant &w : store.wallpapers()) {
            if (w.toMap().value("path").toString().endsWith("aurora-myvatn.jpg"))
                name = w.toMap().value("name").toString();
        }
        QCOMPARE(name, QString::fromUtf8("Mývatn Aurora"));
    }
};

QTEST_GUILESS_MAIN(TestDefaultWallpaper)
#include "test_defaultwallpaper.moc"
